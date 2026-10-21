#import "MMAudio.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <mach/mach_time.h>
#import <libkern/OSAtomic.h>
#import <sys/resource.h>
#import "MMSpotify.h"

// stb_vorbis direkt einbinden (kein separates Kompilat -> keine Doppel-Symbole).
#define STB_VORBIS_NO_STDIO
#define STB_VORBIS_NO_PUSHDATA_API
#include "stb_vorbis.c"

#define NUMBUF 3
#define BUFFRAMES 8192   // Frames pro Puffer

static AudioQueueRef gAQ=NULL;
static stb_vorbis *gV=NULL;
static NSData *gOgg=nil;        // festhalten: stb_vorbis liest direkt aus diesem Speicher
static int gCh=2;
static double gSampleRate=44100.0, gDuration=0.0, gBaseTime=0.0;
static BOOL gRunning=NO, gPaused=NO;
// ---- Wiedergabe während des Downloads ----
#define STREAM_GUARD (96*1024)   // so weit muss der Download dem Decoder voraus sein (eine Ogg-Seite ist höchstens ~64 KB)
static MMAudioStream *gStream=nil;      // nil = ganze Datei war schon da
static double gSilent=0;                // eingefügte Stille (Sekunden), zählt nicht zur Abspielposition
static double gPendingSeek=-1;          // Spulen vor Ende des Downloads: wird danach nachgeholt
static BOOL gStreamDone=NO;             // AudioQueue-Thread hat das Ende des Downloads gesehen (gStream selbst ändert nur der Main-Thread)
static NSUInteger gPlaySerial=0;        // zählt je Start hoch: nachgeholtes Spulen nur für denselben Titel
static BOOL gDurationExact=YES;
static double gExpected=0;              // Länge aus den Metadaten (Sekunden), bis die Datei ganz da ist
static BOOL gStarved=NO;                // gerade in einer Lade-Lücke (für eine Log-Zeile pro Lücke)

// ---- CPU-Messung (3GS): Dekodierzeit im Verhältnis zur erzeugten Audiodauer + CPU des ganzen Prozesses.
// Alle 30 s Audio eine Zeile ins App-Log. decode 25% = Vorbis braucht ein Viertel eines Kerns.
#define CPU_WINDOW 30.0
static double gDecSec=0, gAudSec=0, gWall0=0, gCpu0=0;
static double nowSec(void){ static mach_timebase_info_data_t tb; if(!tb.denom) mach_timebase_info(&tb); return (double)mach_absolute_time()*tb.numer/tb.denom/1e9; }
static double procCpuSec(void){ struct rusage r; getrusage(RUSAGE_SELF,&r);
    return r.ru_utime.tv_sec+r.ru_utime.tv_usec/1e6+r.ru_stime.tv_sec+r.ru_stime.tv_usec/1e6; }
static void cpuReset(void){ gDecSec=0; gAudSec=0; gWall0=nowSec(); gCpu0=procCpuSec(); }
static void cpuAccount(double dec, int frames){
    gDecSec+=dec; gAudSec+=frames/(gSampleRate>0?gSampleRate:44100.0);
    if(gAudSec<CPU_WINDOW) return;
    double wall=nowSec()-gWall0, cpu=procCpuSec()-gCpu0;
    @autoreleasepool {   // läuft im AudioQueue-Thread ohne eigenen Pool: sonst bliebe jedes Mal der ganze Log-Puffer liegen (~64 KB)
        MMLog(@"cpu: decode %.1f%% of realtime, process %.1f%% (%.0f s audio, %.0f s wall, %d ch, %.0f Hz)",
              100*gDecSec/gAudSec, wall>0?100*cpu/wall:0, gAudSec, wall, gCh, gSampleRate);
    }
    cpuReset();
}

static void streamFailed(void){
    gRunning=NO;
    dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"MMAudioStreamFailed" object:nil]; });
}
static void fillCb(void *ud, AudioQueueRef q, AudioQueueBufferRef buf){
    if(!gV || !gRunning){ buf->mAudioDataByteSize=0; return; }
    short *out=(short*)buf->mAudioData;
    int capShorts=buf->mAudioDataBytesCapacity/(int)sizeof(short);
    MMAudioStream*st=gStream;
    if(st && !gStreamDone){
        BOOL complete=st.complete; OSMemoryBarrier();   // erst das Flag, dann die Bytes
        if(complete){   // Download fertig: genaue Länge, verschobenes Spulen nachholen, ab jetzt normale Wiedergabe
            gStreamDone=YES;
            if(!gDurationExact){ gDuration=stb_vorbis_stream_length_in_seconds(gV); gDurationExact=YES; }   // springt kurz ans Ende und wieder zurück
            if(gPendingSeek>=0){ double ps=gPendingSeek; NSUInteger ser=gPlaySerial; gPendingSeek=-1;
                dispatch_async(dispatch_get_main_queue(), ^{ if(ser==gPlaySerial) [MMAudio seekTo:ps]; }); }
        } else {
            NSUInteger need=167+stb_vorbis_get_file_offset(gV)+STREAM_GUARD, avail=st.avail; OSMemoryBarrier();
            if(need>avail){   // Wiedergabe hat den Download eingeholt
                if(st.failed){ buf->mAudioDataByteSize=0; streamFailed(); return; }
                if(!gStarved){ gStarved=YES; @autoreleasepool { MMLog(@"stream: Wiedergabe hat den Download eingeholt (%.1f MB da) - kurze Pause",st.avail/1048576.0); } }
                int frames=MIN(capShorts/gCh,(int)(gSampleRate/10));   // 0.1 s Stille, dann nochmal schauen
                memset(out,0,frames*gCh*sizeof(short)); gSilent+=frames/gSampleRate;
                buf->mAudioDataByteSize=frames*gCh*(int)sizeof(short); AudioQueueEnqueueBuffer(q,buf,0,NULL); return;
            }
        }
    }
    gStarved=NO;
    double t0=nowSec();
    int got=stb_vorbis_get_samples_short_interleaved(gV,gCh,out,capShorts); // got = Frames pro Kanal
    if(got>0) cpuAccount(nowSec()-t0,got);
    if(got>0 && st && !gStreamDone && !gDurationExact && gExpected<=0){   // ohne Metadaten-Länge schätzen: Bytes pro Sekunde bisher hochgerechnet auf die ganze Datei
        double played=stb_vorbis_get_sample_offset(gV)/(gSampleRate>0?gSampleRate:44100.0); unsigned off=stb_vorbis_get_file_offset(gV);
        if(played>5 && off>0) gDuration=played*(double)(st.data.length-167)/off;
    }
    if(got<=0){ // Ende
        buf->mAudioDataByteSize=0;
        gRunning=NO;
        AudioQueueStop(q,false);  // asynchron auslaufen lassen
        dispatch_async(dispatch_get_main_queue(), ^{   // Track zu Ende -> Auto-Advance
            [[NSNotificationCenter defaultCenter] postNotificationName:@"MMAudioDidFinish" object:nil];
        });
        return;
    }
    buf->mAudioDataByteSize=got*gCh*(int)sizeof(short);
    AudioQueueEnqueueBuffer(q,buf,0,NULL);
}

@implementation MMAudioStream
- (id)initWithLength:(NSUInteger)length { if((self=[super init])) _data=[NSMutableData dataWithLength:length]; return self; }
@end

@implementation MMAudio

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
    gStream=stream; gStreamDone=(stream==nil); gSilent=0; gPendingSeek=-1; gPlaySerial++;
    gDurationExact=(stream==nil || stream.complete);
    gDuration=gDurationExact?stb_vorbis_stream_length_in_seconds(gV):gExpected;   // lädt noch: Länge aus den Metadaten (sonst später geschätzt)
    if(stream.complete) gStreamDone=YES;
    gBaseTime=0; cpuReset();

    AudioStreamBasicDescription a; memset(&a,0,sizeof(a));
    a.mSampleRate=info.sample_rate;
    a.mFormatID=kAudioFormatLinearPCM;
    a.mFormatFlags=kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked;
    a.mBitsPerChannel=16;
    a.mChannelsPerFrame=gCh;
    a.mFramesPerPacket=1;
    a.mBytesPerFrame=2*gCh;
    a.mBytesPerPacket=2*gCh;

    gRunning=YES; gPaused=NO;
    if(AudioQueueNewOutput(&a,fillCb,NULL,NULL,NULL,0,&gAQ)!=0){ [self stop]; return; }
    for(int i=0;i<NUMBUF;i++){
        AudioQueueBufferRef b=NULL;
        AudioQueueAllocateBuffer(gAQ,BUFFRAMES*2*gCh,&b);
        fillCb(NULL,gAQ,b);
    }
    AudioQueueStart(gAQ,NULL);
}

+ (void)stop {
    gRunning=NO;
    if(gAQ){ AudioQueueStop(gAQ,true); AudioQueueDispose(gAQ,true); gAQ=NULL; }
    if(gV){ stb_vorbis_close(gV); gV=NULL; }
    gOgg=nil; gPaused=NO; gStream=nil; gStreamDone=NO; gSilent=0; gPendingSeek=-1; gPlaySerial++;
}

+ (void)setPaused:(BOOL)paused {
    if(!gAQ) return;
    gPaused=paused;
    if(paused) AudioQueuePause(gAQ); else { cpuReset(); AudioQueueStart(gAQ,NULL); }
}

+ (BOOL)isPlaying { return gRunning && !gPaused; }
+ (BOOL)hasEnded { return gAQ!=NULL && !gRunning; }   // Titel bis zum Ende gespielt (Queue gestoppt, aber noch geladen)
+ (BOOL)isLoaded { return gAQ!=NULL; }                 // NO = nichts geladen (gestoppt) -> "Weiter" hätte nichts zum Fortsetzen

+ (double)duration { return gDuration; }

+ (double)currentTime {
    if(!gAQ) return gBaseTime;
    AudioTimeStamp ts; memset(&ts,0,sizeof(ts));
    OSStatus r=AudioQueueGetCurrentTime(gAQ,NULL,&ts,NULL);
    double t=gBaseTime;
    if(r==0 && (ts.mFlags & kAudioTimeStampSampleTimeValid)) t+=ts.mSampleTime/(gSampleRate>0?gSampleRate:44100.0)-gSilent;   // eingefügte Stille zählt nicht
    if(t<0) t=0; if(gDuration>0 && t>gDuration) t=gDuration;
    return t;
}

+ (void)seekTo:(double)seconds {
    if(!gV) return;
    MMAudioStream*st=gStream;
    if(st && !st.complete){ gPendingSeek=seconds; return; }   // Spulen braucht das Dateiende -> nach dem Download nachholen
    if(seconds<0)seconds=0; if(gDuration>0&&seconds>gDuration)seconds=gDuration;
    BOOL wasPaused=gRunning && gPaused;   // pausiert gespult: an der neuen Stelle pausiert bleiben (Play setzt fort)
    if(gAQ){ AudioQueueStop(gAQ,true); AudioQueueDispose(gAQ,true); gAQ=NULL; }
    stb_vorbis_seek(gV,(unsigned int)(seconds*gSampleRate));
    gBaseTime=seconds; gSilent=0; gRunning=YES; gPaused=wasPaused; cpuReset();
    AudioStreamBasicDescription a; memset(&a,0,sizeof(a));
    a.mSampleRate=gSampleRate; a.mFormatID=kAudioFormatLinearPCM;
    a.mFormatFlags=kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked;
    a.mBitsPerChannel=16; a.mChannelsPerFrame=gCh; a.mFramesPerPacket=1; a.mBytesPerFrame=2*gCh; a.mBytesPerPacket=2*gCh;
    if(AudioQueueNewOutput(&a,fillCb,NULL,NULL,NULL,0,&gAQ)!=0) return;
    for(int i=0;i<NUMBUF;i++){ AudioQueueBufferRef b=NULL; AudioQueueAllocateBuffer(gAQ,BUFFRAMES*2*gCh,&b); fillCb(NULL,gAQ,b); }
    if(!wasPaused) AudioQueueStart(gAQ,NULL);   // pausiert: Puffer sind gefüllt, setPaused:NO startet die Warteschlange
}


@end
