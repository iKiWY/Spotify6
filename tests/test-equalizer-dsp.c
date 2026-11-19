#include "../music/Spot/MMEqualizerDSP.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define PI 3.14159265358979323846

static double tone_rms(unsigned band, double gain, double frequency) {
    MMEQState s={0};
    const unsigned rate=44100, frames=rate;
    short *pcm=calloc(frames, sizeof(short));
    assert(pcm);
    MMEQInit(&s,rate);
    MMEQSetGain(&s,band,gain);
    for(unsigned i=0;i<frames;i++) pcm[i]=(short)(12000*sin(2*PI*frequency*i/rate));
    MMEQProcess(&s,pcm,frames,1);
    double sum=0;
    for(unsigned i=rate/2;i<frames;i++){ double x=pcm[i]; sum+=x*x; }
    free(pcm);
    return sqrt(sum/(frames-rate/2));
}

int main(void) {
    MMEQState s={0};
    short input[]={1000,-1000,2000,-2000,3000,-3000}, original[6];
    memcpy(original,input,sizeof(input));
    MMEQInit(&s,44100);
    MMEQProcess(&s,input,3,2);
    assert(memcmp(input,original,sizeof(input))==0); /* flat response is unity */

    double flat=tone_rms(5,0,1000), boosted=tone_rms(5,6,1000), cut=tone_rms(5,-6,1000);
    assert(boosted>flat*1.8 && boosted<flat*2.2);
    assert(cut<flat*0.6 && cut>flat*0.45);

    memset(&s,0,sizeof(s));
    MMEQSetGain(&s,9,20); /* can be set before sample-rate initialization */
    MMEQInit(&s,32000);
    assert(s.gains[9]==12);
    assert(isfinite(s.filters[9].b0));
    short impulse[20000]={32767};
    MMEQProcess(&s,impulse,20000,1);
    for(unsigned i=0;i<20000;i++) assert(impulse[i]>=-32768 && impulse[i]<=32767);

    printf("equalizer DSP tests passed\n");
    return 0;
}
