#ifndef MM_EQUALIZER_DSP_H
#define MM_EQUALIZER_DSP_H
#define MM_EQ_BANDS 10
typedef struct { double b0,b1,b2,a1,a2,z1[2],z2[2]; } MMEQFilter;
typedef struct { MMEQFilter filters[MM_EQ_BANDS]; double sampleRate; double gains[MM_EQ_BANDS]; } MMEQState;
extern const double MMEQFrequencies[MM_EQ_BANDS];
void MMEQInit(MMEQState *state, double sampleRate);
void MMEQSetGain(MMEQState *state, unsigned band, double gainDB);
void MMEQProcess(MMEQState *state, short *interleaved, unsigned frames, unsigned channels);
#endif
