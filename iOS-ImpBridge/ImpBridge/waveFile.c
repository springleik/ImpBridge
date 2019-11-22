//
//  waveFile.c
//  ImpBridge
//
//  Created by Mark Williamsen on 12/4/11.
//  for talk #61 given April 25, 2016 at SDiOS.
//  You may use this code however you like,
//  but realize that the burden of verification
//  and validation rests with you alone.
//  http://www.williamsonic.com
//  http://www.sdios.org
//

#include <stdio.h>
#include <string.h>
#include <math.h>
#include <complex.h>

#include "waveFile.h"

// populate wave file struct, clear data buffer
// assumes memory already allocated
void setSize(struct waveFile *theWave, int sampleCount)
{
    // assume 2 channels, 2 bytes each, per sample
    int byteCount = sampleCount * 4;
    
    // set data chunk
    memcpy(theWave->dataHead.chunkID, "data", 4);
    theWave->dataHead.chunkSize = byteCount;
    memset(theWave->theData, 0, byteCount);
    
    // set filler chunk
    memcpy(theWave->fllrHead.chunkID, "FLLR", 4);
    theWave->fllrHead.chunkSize = 4044;
    memset(theWave->theFiller, 0, 4044);
    
    // set fmt chunk
    memcpy(theWave->fmtHead.chunkID, "fmt ", 4);
    theWave->fmtHead.chunkSize = 16;
    theWave->fmtCode = 1;
    theWave->numChan = 2;
    theWave->sampRate = 44100;
    theWave->byteRate = 4 * 44100;
    theWave->blockAlign = 4;
    theWave->bitsSamp = 16;
    
    // set riff chunk
    memcpy(theWave->riffHead.chunkID, "RIFF", 4);
    theWave->riffHead.chunkSize = byteCount + 12 + 24 + 4052;
    memcpy(theWave->format, "WAVE", 4);
}

int n = 0, m = 0;
complex double
    z1  = 1.0,
    z2  = 1.0,
    e1  = 15000.0,  // left drive voltage
    e2  = 0.0,      // right drive voltage
    e3  = 0.0,      // mic input voltage
    e4  = 0.0,      // orthogonal background
    e1p = 0.0,
    e2p = 15000.0,
    e3p = 0.0,
    e4p = 0.0;
int frq = 1000;

// fill buffer with continuous wave (CW) stimulus, assumes buffer is already allocated
void fillWave(struct waveFile *theWave)
{
    // dump out if buffer not adequate
    if (!theWave) {return;}
    complex double scaledOmega = -frq * 2. * M_PI / 44100.0 * I;
    if (theWave->dataHead.chunkSize < (4 * nSamp)) {return;}
    
    // pad with zeros (100 msec)
    for (n = 0; n < (2 * nSamp/10); n++)
    {
        theWave->theData[2*n]   = (signed short)0;
        theWave->theData[2*n+1] = (signed short)0;
    }
    
    // first measurement (200 msec)
    for (n = (2 * nSamp/10); n < (6 * nSamp/10); n++)
    {
        theWave->theData[2*n]   = (signed short)cimag(e1 * cexp(scaledOmega * n));
        theWave->theData[2*n+1] = (signed short)cimag(e2 * cexp(scaledOmega * n));
    }
    
    // second measurement (200 msec)
    for (n = (6 * nSamp/10); n < nSamp; n++)
    {
        theWave->theData[2*n]   = (signed short)cimag(e1p * cexp(scaledOmega * n));
        theWave->theData[2*n+1] = (signed short)cimag(e2p * cexp(scaledOmega * n));
    }
}

// analyze recorded wave file to get complex amplitudes
void analyzeWave(const struct waveFile *theWave)
{
    // use matched filters to obtain complex response and background
    // look at 100 msec in middle of first and second measurements
    z1 = z2 = e3 = e3p = e4 = e4p = 0.0;
    complex double scaledOmega = frq * 2.0 * M_PI / 44100.0 * I;    // fundamental excitation
    complex double bkgOmega = 3.0 * scaledOmega / 2.0;  // orthogonal harmonic of fundamental
    for (n = (3 * nSamp/10), m = (7 * nSamp/10); n < (5 * nSamp/10); n++, m++)
    {
        e3  += theWave->theData[2*n] * cexp(scaledOmega * n);
        e3p += theWave->theData[2*m] * cexp(scaledOmega * n);
        e4  += theWave->theData[2*n] * cexp(bkgOmega * n);
        e4p += theWave->theData[2*m] * cexp(bkgOmega * n);
    }
    
    // scale to number of samples
    e3  /= (2 * nSamp/10);  // detector input, first measurement
    e3p /= (2 * nSamp/10);  // detector input, second measurement
    e4  /= (2 * nSamp/10);  // detector background, first measurement
    e4p /= (2 * nSamp/10);  // detector background, second measurement
    
    // set reference, compute ratio of bridge arms
    complex double ratio = (e3p * e1 - e3 * e1p) / (e3 * e2p - e3p * e2);
    z1 = 1.0;
    z2 = z1 / ratio;
}

#define realImag(A) creal(A), cimag(A)
char resultString[1024] = {'\0'};

// items separated by newlines, for display on device
char *getResult(void)
{
    sprintf(resultString,
            "z1:  %f%+fi\n"
            "z2:  %f%+fi\n"
            "e1:  %f%+fi\n"
            "e2:  %f%+fi\n"
            "e3:  %f%+fi\n"
            "e4:  %f%+fi\n"
            "e1p: %f%+fi\n"
            "e2p: %f%+fi\n"
            "e3p: %f%+fi\n"
            "e4p: %f%+fi\n"
            "frq: %d",
            realImag(z1),
            realImag(z2),
            realImag(e1),
            realImag(e2),
            realImag(e3),
            realImag(e4),
            realImag(e1p),
            realImag(e2p),
            realImag(e3p),
            realImag(e4p),
            frq);
    
    return resultString;
}

char logString[1024] = {'\0'};
char *logHeading(void)
{
    sprintf(logString, "z1,z2,e1,e2,e3,e4,e1p,e2p,e3p,e4p,freq\n");
    return logString;
}

// items separated by commas, for analysis in Excel
char resultLog[1024] = {'\0'};
char *logResult(void)
{
    sprintf(resultLog,
            "%f%+fi,"
            "%f%+fi,"
            "%f%+fi,"
            "%f%+fi,"
            "%f%+fi,"
            "%f%+fi,"
            "%f%+fi,"
            "%f%+fi,"
            "%f%+fi,"
            "%f%+fi,"
            "%d\n",
            realImag(z1),
            realImag(z2),
            realImag(e1),
            realImag(e2),
            realImag(e3),
            realImag(e4),
            realImag(e1p),
            realImag(e2p),
            realImag(e3p),
            realImag(e4p),
            frq);
    
    return resultLog;
}

// copy in params, enforce limits
void setParams(complex double e1param, complex double e2param,
               complex double e1pparam, complex double e2pparam, int freq)
{
    e1  = e1param;
    e2  = e2param;
    e1p = e1pparam;
    e2p = e2pparam;
    frq = freq;
    if (frq < 20.0) {frq = 20.0;}
    if (frq > 20000.0) {frq = 20000.0;}
}

// copy out params
void getParams(complex double *e3param, complex double *e3pparam,
               complex double *e4param, complex double *e4pparam)
{
    *e3param  = e3;     // detector input, first measurement
    *e3pparam = e3p;    // detector input, second measurement
    *e4param  = e4;     // detector background, first measurement
    *e4pparam = e4p;    // detector background, second measurement
}

// needed to scale horizontal axis of waveform plot
double getFreq(void)
{
    return frq;
}

