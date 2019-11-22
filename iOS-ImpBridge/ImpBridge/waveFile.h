//
//  waveFile.h
//  AudioPad
//
//  Created by Mark Williamsen on 12/4/11.
//  for talk #61 given April 25, 2016 at SDiOS.
//  You may use this code however you like,
//  but realize that the burden of verification
//  and validation rests with you alone.
//  http://www.williamsonic.com
//  http://www.sdios.org
//

#ifndef AudioPad_waveFile_h
#define AudioPad_waveFile_h

#define nSamp 22050 // 10 quanta of 2205 samples each

// wave file chunk header, exactly 8 bytes
struct chunkHead
{
    char chunkID[4];
    int chunkSize;
};

// wave file header structure, assumes chunks don't move around
struct waveFile
{
    // RIFF chunk, exactly 12 bytes
    struct chunkHead riffHead;
    char format[4];
    
    // fmt chunk, exactly 24 bytes
    struct chunkHead fmtHead;
    short fmtCode;
    short numChan;
    int sampRate;
    int byteRate;
    short blockAlign;
    short bitsSamp;
    
    // filler chunk, exactly 4052 bytes
    struct chunkHead fllrHead;
    char theFiller[4044];
    
    // data chunk, 8 bytes plus audio samples
    struct chunkHead dataHead;
    signed short theData[nSamp * 2];
};

// methods related to audio subsystem
void setSize(struct waveFile *, int);
void fillWave(struct waveFile *);
void analyzeWave(const struct waveFile *);
char *getResult(void);
char *logHeading(void);
char *logResult(void);
void setParams(complex double, complex double,
               complex double, complex double, int);
void getParams(complex double *, complex double *,
               complex double *, complex double *);
double getFreq(void);

#endif
