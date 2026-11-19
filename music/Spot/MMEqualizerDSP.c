#include "MMEqualizerDSP.h"
#include <math.h>
#include <string.h>

const double MMEQFrequencies[MM_EQ_BANDS]={31.25,62.5,125,250,500,1000,2000,4000,8000,16000};

static void configure(MMEQState *s, unsigned i) {
    MMEQFilter *f=&s->filters[i];
    double nyquist=s->sampleRate*0.49;
    double hz=MMEQFrequencies[i] < nyquist ? MMEQFrequencies[i] : nyquist;
    double A=pow(10.0,s->gains[i]/40.0), w=6.283185307179586*hz/s->sampleRate;
    double sn=sin(w), cs=cos(w), alpha=sn*sinh(log(2.0)*0.5);
    double a0=1.0+alpha/A;
    f->b0=(1.0+alpha*A)/a0; f->b1=(-2.0*cs)/a0; f->b2=(1.0-alpha*A)/a0;
    f->a1=(-2.0*cs)/a0; f->a2=(1.0-alpha/A)/a0;
}

void MMEQInit(MMEQState *s, double rate) {
    unsigned i;
    if(!s)return;
    if(rate<8000.0) rate=44100.0;
    s->sampleRate=rate;
    for(i=0;i<MM_EQ_BANDS;i++){
        s->filters[i].z1[0]=s->filters[i].z1[1]=0;
        s->filters[i].z2[0]=s->filters[i].z2[1]=0;
        configure(s,i);
    }
}

void MMEQSetGain(MMEQState *s, unsigned band, double db) {
    if(!s || band>=MM_EQ_BANDS)return;
    if(db < -12)db=-12;
    if(db>12)db=12;
    s->gains[band]=db;
    if(s->sampleRate>=8000.0) configure(s,band);
}

void MMEQProcess(MMEQState *s, short *pcm, unsigned frames, unsigned channels) {
    unsigned n,c,i;
    if(!s||!pcm||!channels||channels>2||s->sampleRate<8000.0)return;
    for(n=0;n<frames;n++)for(c=0;c<channels;c++){
        double y=pcm[n*channels+c];
        for(i=0;i<MM_EQ_BANDS;i++){
            MMEQFilter*f=&s->filters[i];
            double o=f->b0*y+f->z1[c];
            f->z1[c]=f->b1*y-f->a1*o+f->z2[c];
            f->z2[c]=f->b2*y-f->a2*o;
            y=o;
        }
        if(y>32767)y=32767;
        if(y< -32768)y=-32768;
        pcm[n*channels+c]=(short)y;
    }
}
