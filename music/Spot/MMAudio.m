#import "MMAudio.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <mach/mach_time.h>
#import <libkern/OSAtomic.h>
#import <sys/resource.h>
#import <math.h>
#import "MMSpotify.h"
#import "MMEqualizer.h"

// stb_vorbis direkt einbinden (kein separates Kompilat -> keine Doppel-Symbole).
#define STB_VORBIS_NO_STDIO
#define STB_VORBIS_NO_PUSHDATA_API
#include "stb_vorbis.c"

#define OUTPUT_SAMPLE_RATE 44100.0
static AUGraph gGraph=NULL;
static AUNode gConverterNode=0, gEQNode=0, gOutputConverterNode=0, gOutputNode=0;
static AudioUnit gConverterUnit=NULL, gEQUnit=NULL, gOutputConverterUnit=NULL, gOutputUnit=NULL;
static stb_vorbis *gV=NULL;
static NSData *gOgg=nil;        // festhalten: stb_vorbis liest direkt aus diesem Speicher
static int gCh=2;
static double gSampleRate=44100.0, gDuration=0.0, gBaseTime=0.0;
static BOOL gRunning=NO, gPaused=NO;
// ---- Wiedergabe während des Downloads ----
#define STREAM_GUARD (96*1024)   // so weit muss der Download dem Decoder voraus sein (eine Ogg-Seite ist höchstens ~64 KB)
static MMAudioStream *gStream=nil;      // nil = ganze Datei war schon da
static volatile int64_t gPlayedFrames=0;  // von stb_vorbis gelieferte Frames (ohne Buffering-Stille)
static double gPendingSeek=-1;          // Spulen vor Ende des Downloads: wird danach nachgeholt
static BOOL gStreamDone=NO;             // Audio-Render-Thread hat das Ende des Downloads gesehen (gStream selbst ändert nur der Main-Thread)
static NSUInteger gPlaySerial=0;        // zählt je Start hoch: nachgeholtes Spulen nur für denselben Titel
static BOOL gDurationExact=YES;
static double gExpected=0;              // Länge aus den Metadaten (Sekunden), bis die Datei ganz da ist
static BOOL gStarved=NO;                // gerade in einer Lade-Lücke (für eine Log-Zeile pro Lücke)
static BOOL gFinishPending=NO;
static BOOL gEQEnabled=NO, gEQLoaded=NO;
static double gEQGains[10]={0};

// ---- CPU-Messung (3GS): Dekodierzeit im Verhältnis zur erzeugten Audiodauer + CPU des ganzen Prozesses.
// Alle 30 s Audio eine Zeile ins App-Log. decode 25% = Vorbis braucht ein Viertel eines Kerns.
#define CPU_WINDOW 30.0
static double gDecSec=0, gAudSec=0, gWall0=0, gCpu0=0;
static double nowSec(void){ static mach_timebase_info_data_t tb; if(!tb.denom) mach_timebase_info(&tb); return (double)mach_absolute_time()*tb.numer/tb.denom/1e9; }
static double procCpuSec(void){ struct rusage r; getrusage(RUSAGE_SELF,&r);
    return r.ru_utime.tv_sec+r.ru_utime.tv_usec/1e6+r.ru_stime.tv_sec+r.ru_stime.tv_usec/1e6; }
static void cpuReset(void){ gDecSec=0; gAudSec=0; gWall0=nowSec(); gCpu0=procCpuSec(); }
static int64_t playedFrames(void){ return OSAtomicAdd64Barrier(0,(volatile int64_t *)&gPlayedFrames); }
static void cpuAccount(double dec, int frames){
    gDecSec+=dec; gAudSec+=frames/(gSampleRate>0?gSampleRate:44100.0);
    if(gAudSec<CPU_WINDOW) return;
    double wall=nowSec()-gWall0, cpu=procCpuSec()-gCpu0;
    @autoreleasepool {   // läuft im Audio-Render-Thread ohne eigenen Pool: sonst bliebe jedes Mal der ganze Log-Puffer liegen (~64 KB)
        MMLog(@"cpu: decode %.1f%% of realtime, process %.1f%% (%.0f s audio, %.0f s wall, %d ch, %.0f Hz)",
              100*gDecSec/gAudSec, wall>0?100*cpu/wall:0, gAudSec, wall, gCh, gSampleRate);
    }
    cpuReset();
}

static void streamFailed(void){
    gRunning=NO; NSUInteger serial=gPlaySerial;
    dispatch_async(dispatch_get_main_queue(), ^{
        if(serial==gPlaySerial){ [MMAudio stop]; [[NSNotificationCenter defaultCenter] postNotificationName:@"MMAudioStreamFailed" object:nil]; }
    });
}

static void finishGraph(NSUInteger serial){
    if(serial!=gPlaySerial || !gGraph)return;
    AUGraphStop(gGraph);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MMAudioDidFinish" object:nil];
}

static OSStatus renderDecoded(void *refCon, AudioUnitRenderActionFlags *flags,
                              const AudioTimeStamp *timeStamp, UInt32 bus,
                              UInt32 frames, AudioBufferList *ioData){
    (void)refCon; (void)timeStamp; (void)bus;
    if(!ioData || ioData->mNumberBuffers<1 || !ioData->mBuffers[0].mData)return kAudio_ParamError;
    AudioBuffer *buffer=&ioData->mBuffers[0];
    UInt32 requestedFrames=frames;
    short *out=(short*)buffer->mData;
    buffer->mDataByteSize=requestedFrames*gCh*(UInt32)sizeof(short);
    buffer->mNumberChannels=(UInt32)gCh;
    if(!gV || !gRunning){ memset(out,0,buffer->mDataByteSize); if(flags)*flags|=kAudioUnitRenderAction_OutputIsSilence; return noErr; }

    MMAudioStream*st=gStream;
    if(st && !gStreamDone){
        BOOL complete=st.complete; OSMemoryBarrier();
        if(complete){
            gStreamDone=YES;
            if(!gDurationExact){ gDuration=stb_vorbis_stream_length_in_seconds(gV); gDurationExact=YES; }
            if(gPendingSeek>=0){ double ps=gPendingSeek; NSUInteger ser=gPlaySerial; gPendingSeek=-1;
                dispatch_async(dispatch_get_main_queue(), ^{ if(ser==gPlaySerial) [MMAudio seekTo:ps]; }); }
        } else {
            NSUInteger need=167+stb_vorbis_get_file_offset(gV)+STREAM_GUARD, avail=st.avail; OSMemoryBarrier();
            if(need>avail){
                if(st.failed){ memset(out,0,buffer->mDataByteSize); if(flags)*flags|=kAudioUnitRenderAction_OutputIsSilence; streamFailed(); return noErr; }
                if(!gStarved){ gStarved=YES; @autoreleasepool { MMLog(@"stream: Wiedergabe hat den Download eingeholt (%.1f MB da) - kurze Pause",st.avail/1048576.0); } }
                memset(out,0,buffer->mDataByteSize);
                if(flags)*flags|=kAudioUnitRenderAction_OutputIsSilence;
                return noErr;
            }
        }
    }
    gStarved=NO;
    double t0=nowSec();
    int got=stb_vorbis_get_samples_short_interleaved(gV,gCh,out,(int)(requestedFrames*gCh));
    if(got>0){ OSAtomicAdd64Barrier(got,(volatile int64_t *)&gPlayedFrames); cpuAccount(nowSec()-t0,got); }
    if(got>0 && st && !gStreamDone && !gDurationExact && gExpected<=0){
        double played=stb_vorbis_get_sample_offset(gV)/(gSampleRate>0?gSampleRate:44100.0); unsigned off=stb_vorbis_get_file_offset(gV);
        if(played>5 && off>0) gDuration=played*(double)(st.data.length-167)/off;
    }
    if(got<=0){
        memset(out,0,buffer->mDataByteSize);
        if(flags)*flags|=kAudioUnitRenderAction_OutputIsSilence;
        if(!gFinishPending){
            gRunning=NO; gFinishPending=YES; NSUInteger serial=gPlaySerial;
            dispatch_async(dispatch_get_main_queue(), ^{ finishGraph(serial); });
        }
        return noErr;
    }
    UInt32 gotBytes=(UInt32)got*gCh*(UInt32)sizeof(short);
    if(gotBytes<buffer->mDataByteSize) memset((char*)out+gotBytes,0,buffer->mDataByteSize-gotBytes);
    return noErr;
}

static OSStatus setStreamFormat(AudioUnit unit, AudioUnitScope scope, AudioUnitElement element,
                                AudioStreamBasicDescription *format){
    return AudioUnitSetProperty(unit,kAudioUnitProperty_StreamFormat,scope,element,format,sizeof(*format));
}

static Float32 equalizerPreamp(void){
    Float32 maxGain=0;
    for(UInt32 i=0;i<10;i++)if(gEQGains[i]>maxGain)maxGain=(Float32)gEQGains[i];
    return gEQEnabled?-maxGain:0.0f;
}

static void applyEQState(void){
    if(!gEQUnit)return;
    AudioUnitSetParameter(gEQUnit,kAUNBandEQParam_GlobalGain,kAudioUnitScope_Global,0,equalizerPreamp(),0);
    for(UInt32 i=0;i<10;i++)
        AudioUnitSetParameter(gEQUnit,kAUNBandEQParam_BypassBand+i,kAudioUnitScope_Global,0,
                              (gEQEnabled && fabs(gEQGains[i])>0.001)?0.0f:1.0f,0);
}

static void applyEQParameters(void){
    if(!gEQUnit)return;
    for(UInt32 i=0;i<10;i++){
        Float32 freq=(Float32)[MMEqualizer frequencyForBand:i];
        if(freq>OUTPUT_SAMPLE_RATE*0.48)freq=(Float32)(OUTPUT_SAMPLE_RATE*0.48);
        AudioUnitSetParameter(gEQUnit,kAUNBandEQParam_FilterType+i,kAudioUnitScope_Global,0,kAUNBandEQFilterType_Parametric,0);
        AudioUnitSetParameter(gEQUnit,kAUNBandEQParam_Frequency+i,kAudioUnitScope_Global,0,freq,0);
        AudioUnitSetParameter(gEQUnit,kAUNBandEQParam_Gain+i,kAudioUnitScope_Global,0,(Float32)gEQGains[i],0);
        AudioUnitSetParameter(gEQUnit,kAUNBandEQParam_Bandwidth+i,kAudioUnitScope_Global,0,1.0f,0);
    }
    applyEQState();
}

static BOOL createGraph(void){
    const char *stage="NewAUGraph";
    OSStatus status=NewAUGraph(&gGraph); if(status)return NO;
    AudioComponentDescription c; memset(&c,0,sizeof(c)); c.componentManufacturer=kAudioUnitManufacturer_Apple;
    c.componentType=kAudioUnitType_FormatConverter; c.componentSubType=kAudioUnitSubType_AUConverter;
    stage="add decoder converter"; if((status=AUGraphAddNode(gGraph,&c,&gConverterNode)))goto fail;
    c.componentType=kAudioUnitType_Effect; c.componentSubType=kAudioUnitSubType_NBandEQ;
    stage="add NBandEQ"; if((status=AUGraphAddNode(gGraph,&c,&gEQNode)))goto fail;
    c.componentType=kAudioUnitType_FormatConverter; c.componentSubType=kAudioUnitSubType_AUConverter;
    stage="add output converter"; if((status=AUGraphAddNode(gGraph,&c,&gOutputConverterNode)))goto fail;
    c.componentType=kAudioUnitType_Output; c.componentSubType=kAudioUnitSubType_RemoteIO;
    stage="add RemoteIO"; if((status=AUGraphAddNode(gGraph,&c,&gOutputNode)))goto fail;
    stage="open graph"; if((status=AUGraphOpen(gGraph)))goto fail;
    stage="get decoder converter"; if((status=AUGraphNodeInfo(gGraph,gConverterNode,NULL,&gConverterUnit)))goto fail;
    stage="get NBandEQ"; if((status=AUGraphNodeInfo(gGraph,gEQNode,NULL,&gEQUnit)))goto fail;
    stage="get output converter"; if((status=AUGraphNodeInfo(gGraph,gOutputConverterNode,NULL,&gOutputConverterUnit)))goto fail;
    stage="get RemoteIO"; if((status=AUGraphNodeInfo(gGraph,gOutputNode,NULL,&gOutputUnit)))goto fail;

    // iOS requests 4096-frame slices when the display sleeps. Prepare every
    // processing unit before initialization; RemoteIO is configured by iOS.
    UInt32 maximumFrames=4096;
    stage="decoder converter maximum frames";
    if((status=AudioUnitSetProperty(gConverterUnit,kAudioUnitProperty_MaximumFramesPerSlice,kAudioUnitScope_Global,0,&maximumFrames,sizeof(maximumFrames))))goto fail;
    stage="NBandEQ maximum frames";
    if((status=AudioUnitSetProperty(gEQUnit,kAudioUnitProperty_MaximumFramesPerSlice,kAudioUnitScope_Global,0,&maximumFrames,sizeof(maximumFrames))))goto fail;
    stage="output converter maximum frames";
    if((status=AudioUnitSetProperty(gOutputConverterUnit,kAudioUnitProperty_MaximumFramesPerSlice,kAudioUnitScope_Global,0,&maximumFrames,sizeof(maximumFrames))))goto fail;

    AudioStreamBasicDescription source; memset(&source,0,sizeof(source));
    source.mSampleRate=gSampleRate; source.mFormatID=kAudioFormatLinearPCM;
    source.mFormatFlags=kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked;
    source.mBitsPerChannel=16; source.mChannelsPerFrame=(UInt32)gCh; source.mFramesPerPacket=1;
    source.mBytesPerFrame=2*gCh; source.mBytesPerPacket=2*gCh;
    AudioStreamBasicDescription processing; memset(&processing,0,sizeof(processing));
    processing.mSampleRate=OUTPUT_SAMPLE_RATE; processing.mFormatID=kAudioFormatLinearPCM;
processing.mBitsPerChannel=32; processing.mChannelsPerFrame=(UInt32)gCh; processing.mFramesPerPacket=1;
    processing.mBytesPerFrame=sizeof(Float32); processing.mBytesPerPacket=sizeof(Float32);
    AudioStreamBasicDescription device; memset(&device,0,sizeof(device));
    device.mSampleRate=OUTPUT_SAMPLE_RATE; device.mFormatID=kAudioFormatLinearPCM;
    device.mFormatFlags=kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked;
    device.mBitsPerChannel=16; device.mChannelsPerFrame=(UInt32)gCh; device.mFramesPerPacket=1;
    device.mBytesPerFrame=2*gCh; device.mBytesPerPacket=2*gCh;
    AudioStreamBasicDescription eqDefault; memset(&eqDefault,0,sizeof(eqDefault)); UInt32 eqSize=sizeof(eqDefault);
    OSStatus eqGet=AudioUnitGetProperty(gEQUnit,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Input,0,&eqDefault,&eqSize);
    AudioStreamBasicDescription eqOutDefault; memset(&eqOutDefault,0,sizeof(eqOutDefault)); eqSize=sizeof(eqOutDefault);
    OSStatus eqOutGet=AudioUnitGetProperty(gEQUnit,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Output,0,&eqOutDefault,&eqSize);
    stage="query NBandEQ format";
    if(eqGet || eqOutGet || eqDefault.mFormatID!=eqOutDefault.mFormatID || eqDefault.mFormatFlags!=eqOutDefault.mFormatFlags || eqDefault.mChannelsPerFrame!=eqOutDefault.mChannelsPerFrame || eqDefault.mSampleRate!=eqOutDefault.mSampleRate){
        status=eqGet?eqGet:(eqOutGet?eqOutGet:kAudioUnitErr_FormatNotSupported); goto fail;
    }
    processing=eqDefault;
    stage="decoder converter input format"; if((status=setStreamFormat(gConverterUnit,kAudioUnitScope_Input,0,&source)))goto fail;
    stage="decoder converter output format"; if((status=setStreamFormat(gConverterUnit,kAudioUnitScope_Output,0,&processing)))goto fail;
    // Keep NBandEQ's own supported input/output formats; explicitly setting even its reported
    // default format returns kAudioUnitErr_FormatNotSupported on the iPhone 4's iOS audio unit.
    stage="output converter input format"; if((status=setStreamFormat(gOutputConverterUnit,kAudioUnitScope_Input,0,&processing)))goto fail;
    stage="output converter output format"; if((status=setStreamFormat(gOutputConverterUnit,kAudioUnitScope_Output,0,&device)))goto fail;
    stage="RemoteIO input format"; if((status=setStreamFormat(gOutputUnit,kAudioUnitScope_Input,0,&device)))goto fail;

    UInt32 bands=10;
    stage="NBandEQ band count"; if((status=AudioUnitSetProperty(gEQUnit,kAUNBandEQProperty_NumberOfBands,kAudioUnitScope_Global,0,&bands,sizeof(bands))))goto fail;
    AURenderCallbackStruct input; input.inputProc=renderDecoded; input.inputProcRefCon=NULL;
    stage="render callback"; if((status=AudioUnitSetProperty(gConverterUnit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&input,sizeof(input))))goto fail;
    stage="connect converter to EQ"; if((status=AUGraphConnectNodeInput(gGraph,gConverterNode,0,gEQNode,0)))goto fail;
    stage="connect EQ to output converter"; if((status=AUGraphConnectNodeInput(gGraph,gEQNode,0,gOutputConverterNode,0)))goto fail;
    stage="connect output converter to RemoteIO"; if((status=AUGraphConnectNodeInput(gGraph,gOutputConverterNode,0,gOutputNode,0)))goto fail;
    applyEQParameters();
    stage="initialize graph"; if((status=AUGraphInitialize(gGraph)))goto fail;
    return YES;
fail:
    MMLog(@"audio: AUGraph setup failed at %@ (%d), source %.0f Hz %d ch",[NSString stringWithUTF8String:stage],(int)status,gSampleRate,gCh);
    if(gGraph){ AUGraphClose(gGraph); DisposeAUGraph(gGraph); }
    gGraph=NULL; gConverterUnit=gEQUnit=gOutputConverterUnit=gOutputUnit=NULL; return NO;
}

@implementation MMAudioStream
- (id)initWithLength:(NSUInteger)length { if((self=[super init])) _data=[NSMutableData dataWithLength:length]; return self; }
@end

@implementation MMAudio

+ (void)setEqualizerEnabled:(BOOL)enabled {
    gEQEnabled=enabled; gEQLoaded=YES; [MMEqualizer saveEnabled:enabled];
    if(gEQUnit) applyEQState();
}
+ (BOOL)isEqualizerEnabled { return gEQLoaded?gEQEnabled:[[NSUserDefaults standardUserDefaults] boolForKey:@"equalizer.enabled"]; }
+ (void)setEqualizerGain:(double)gain forBand:(NSUInteger)band {
    if(band>=MM_EQUALIZER_BANDS)return;
    [MMEqualizer saveGain:gain forBand:band];
    gEQGains[band]=[MMEqualizer gainForBand:band];
    if(gEQUnit){
        AudioUnitSetParameter(gEQUnit,kAUNBandEQParam_Gain+(UInt32)band,kAudioUnitScope_Global,0,(Float32)gEQGains[band],0);
        AudioUnitSetParameter(gEQUnit,kAUNBandEQParam_BypassBand+(UInt32)band,kAudioUnitScope_Global,0,
                              (gEQEnabled && fabs(gEQGains[band])>0.001)?0.0f:1.0f,0);
        AudioUnitSetParameter(gEQUnit,kAUNBandEQParam_GlobalGain,kAudioUnitScope_Global,0,equalizerPreamp(),0);
    }
}

+ (void)playOgg:(NSData *)ogg { [self start:ogg stream:nil]; }
+ (void)playStream:(MMAudioStream *)stream { [self start:stream.data stream:stream]; }
+ (void)setExpectedDuration:(double)seconds { gExpected=seconds; if(gStream && !gDurationExact && seconds>0) gDuration=seconds; }
+ (MMAudioStream *)currentStream { return gStream; }
+ (BOOL)isBuffering { MMAudioStream*st=gStream; return st && !st.complete && gRunning; }   // gStream wird nur auf dem Main-Thread gesetzt
+ (void)start:(NSData *)ogg stream:(MMAudioStream *)stream {
    [self stop];
    if(ogg.length<=167) return;
    // Playback-Session: spielt auch bei Stummschalter & im Hintergrund/gesperrt weiter
    AVAudioSession*as=[AVAudioSession sharedInstance];
    [as setCategory:AVAudioSessionCategoryPlayback error:NULL];
    [as setActive:YES error:NULL];
    gOgg=ogg;
    int err=0;
    gV=stb_vorbis_open_memory((const unsigned char*)ogg.bytes+167,(int)ogg.length-167,&err,NULL);
    if(!gV){ gOgg=nil; return; }
    stb_vorbis_info info=stb_vorbis_get_info(gV);
    gCh=info.channels>0?info.channels:2;
    gSampleRate=info.sample_rate>0?info.sample_rate:44100.0;
    NSArray *saved=[MMEqualizer gains];
    for(NSUInteger i=0;i<10;i++) gEQGains[i]=[saved[i] doubleValue];
    gEQEnabled=[MMEqualizer isEnabled]; gEQLoaded=YES;
    gStream=stream; gStreamDone=(stream==nil); gPendingSeek=-1; gPlaySerial++;
    gDurationExact=(stream==nil || stream.complete);
    gDuration=gDurationExact?stb_vorbis_stream_length_in_seconds(gV):gExpected;   // lädt noch: Länge aus den Metadaten (sonst später geschätzt)
    if(stream.complete) gStreamDone=YES;
    gBaseTime=0; cpuReset();

    gRunning=YES; gPaused=NO; gFinishPending=NO; gPlayedFrames=0;
    if(!createGraph()){ [self stop]; return; }
    if(AUGraphStart(gGraph)!=noErr){ [self stop]; return; }

}

+ (void)stop {
    gRunning=NO;
    if(gGraph){ AUGraphStop(gGraph); AUGraphUninitialize(gGraph); DisposeAUGraph(gGraph); gGraph=NULL; }
    gConverterUnit=gEQUnit=gOutputConverterUnit=gOutputUnit=NULL;
    if(gV){ stb_vorbis_close(gV); gV=NULL; }
    gOgg=nil; gPaused=NO; gStream=nil; gStreamDone=NO; gPlayedFrames=0; gPendingSeek=-1; gFinishPending=NO; gPlaySerial++;
}

+ (void)setPaused:(BOOL)paused {
    if(!gGraph || gPaused==paused)return;
    if(paused){
        if(!gRunning)return;
        gRunning=NO; gPaused=YES;
        AUGraphStop(gGraph);
        gBaseTime=[self currentTime]; gPlayedFrames=0;
    } else {
        if(!gPaused)return;
        gPaused=NO; gRunning=YES; cpuReset();
        OSStatus status=AUGraphStart(gGraph);
        if(status!=noErr){ gRunning=NO; MMLog(@"audio: resume failed (%d)",(int)status); }
    }
}

+ (void)restorePlaybackIfNeeded {
    if(!gGraph || !gRunning || gPaused)return;
    NSError *error=nil;
    BOOL active=[[AVAudioSession sharedInstance] setActive:YES error:&error];
    Boolean running=false;
    OSStatus queryStatus=AUGraphIsRunning(gGraph,&running);
    OSStatus startStatus=noErr;
    if(queryStatus==noErr && !running) startStatus=AUGraphStart(gGraph);
    MMLog(@"audio: restore active=%d sessionError=%@ graphRunning=%d query=%d start=%d",
          active,error.localizedDescription?:@"none",running,(int)queryStatus,(int)startStatus);
}

+ (BOOL)isPlaying { return gRunning && !gPaused; }
+ (BOOL)hasEnded { return gGraph!=NULL && !gRunning && !gPaused; }
+ (BOOL)isLoaded { return gGraph!=NULL && gOgg!=nil; }

+ (double)duration { return gDuration; }

+ (double)currentTime {
    double t=gBaseTime+(double)playedFrames()/(gSampleRate>0?gSampleRate:44100.0);
    if(t<0)t=0; if(gDuration>0 && t>gDuration)t=gDuration;
    return t;
}

+ (void)seekTo:(double)seconds {
    if(!gV)return;
    MMAudioStream*st=gStream;
    if(st && !st.complete){ gPendingSeek=seconds; return; }
    if(seconds<0)seconds=0; if(gDuration>0&&seconds>gDuration)seconds=gDuration;
    BOOL wasPaused=gPaused;
    if(gRunning){ gRunning=NO; AUGraphStop(gGraph); }
    stb_vorbis_seek(gV,(unsigned int)(seconds*gSampleRate));
    gBaseTime=seconds; gPlayedFrames=0; gRunning=!wasPaused; gPaused=wasPaused; gFinishPending=NO; cpuReset();
    if(gConverterUnit) AudioUnitReset(gConverterUnit,kAudioUnitScope_Global,0);
    if(gEQUnit) AudioUnitReset(gEQUnit,kAudioUnitScope_Global,0);
    if(gGraph && !wasPaused && AUGraphStart(gGraph)!=noErr)gRunning=NO;
}



@end
