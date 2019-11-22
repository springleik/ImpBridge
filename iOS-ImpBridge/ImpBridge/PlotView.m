//
//  PlotView.m
//  ImpBridge
//
//  Created by Mark Williamsen on 5/24/15.
//  for talk #61 given April 25, 2016 at SDiOS.
//  You may use this code however you like,
//  but realize that the burden of verification
//  and validation rests with you alone.
//  http://www.williamsonic.com
//  http://www.sdios.org
//

#import <complex.h>

#import "waveFile.h"
#import "ViewController.h"
#import "PlotView.h"

@implementation PlotView

@synthesize theView;

// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    
    // Drawing code
    CGContextRef gc = UIGraphicsGetCurrentContext();
    CGContextSetLineWidth(gc, 1);
    CGContextSetStrokeColorWithColor(gc, [UIColor darkGrayColor].CGColor);
    int n, m;
    for (n = 294; n < 4410; n+= 294)
    {// draw horizontal ticks
        CGContextMoveToPoint(gc, n * 300.0 / 4410.0, 0.0);
        if (n % 1470) {CGContextAddLineToPoint(gc, n * 300.0 / 4410.0, 8.0);}
        else  {CGContextAddLineToPoint(gc, n * 300.0 / 4410.0, 15.0);}

        CGContextMoveToPoint(gc, n * 300.0 / 4410.0, 250.0);
        if (n % 1470) {CGContextAddLineToPoint(gc, n * 300.0 / 4410.0, 242.0);}
        else {CGContextAddLineToPoint(gc, n * 300.0 / 4410.0, 235.0);}
    }
    for (n = 25; n < 250; n += 25)
    {// draw vertical ticks
        CGContextMoveToPoint(gc, 0.0, n);
        if (n % 125) {CGContextAddLineToPoint(gc, 8.0, n);}
        else {CGContextAddLineToPoint(gc, 15.0, n);}
        
        CGContextMoveToPoint(gc, 300.0, n);
        if (n % 125) {CGContextAddLineToPoint(gc, 292.0, n);}
        else {CGContextAddLineToPoint(gc, 285.0, n);}
        
    }
    CGContextStrokePath(gc);
    
    // get wave data from view controller
    const struct waveFile *playWave = theView.playData.mutableBytes;
    const struct waveFile *recWave = theView.recordData.bytes;
    
    // set limits, compute points per cycle, estimate skip interval
    double theFreq = getFreq();
    if (theFreq < 20.0) {theFreq = 20.0;}
    if (theFreq > 20000.0) {theFreq = 20000.0;}
    int pointsCycle = 44100/theFreq+1;
    int skipInterval = 1;
    bool first = true;
    while (pointsCycle > 50)
    {
        skipInterval++;
        pointsCycle = 44100/theFreq/skipInterval+1;
    }
    NSLog(@"pointsCycle: %d, skipInterval: %d", pointsCycle, skipInterval);
    
    if (playWave)
    {
        // draw lines between samples
        CGContextSetStrokeColorWithColor(gc, [UIColor purpleColor].CGColor);
        for (n = 0, m = 2*(3*nSamp/10), first = true; n <= pointsCycle; n++, m+= 2*skipInterval)
        {
            short samp = playWave->theData[m];
            if (first)
            {
                first = false;
                CGContextMoveToPoint(gc, 0.0, samp/256.0+125.0);
            }
            else
            {
                CGContextAddLineToPoint(gc, n*300.0/pointsCycle, samp/256.0+125.0);
            }
        }
        CGContextStrokePath(gc);
        for (n = 0, m = 2*(7*nSamp/10)+1, first = true; n <= pointsCycle; n++, m+= 2*skipInterval)
        {
            short samp = playWave->theData[m];
            if (first)
            {
                first = false;
                CGContextMoveToPoint(gc, 0.0, samp/256.0+125.0);
            }
            else
            {
                CGContextAddLineToPoint(gc, n*300.0/pointsCycle, samp/256.0+125.0);
            }
        }
        CGContextStrokePath(gc);
        
        // draw dots on top of samples
        CGContextSetFillColorWithColor(gc, [UIColor purpleColor].CGColor);
        for (n = 0, m = 2*(3*nSamp/10), first = true; n <= pointsCycle; n++, m+= 2*skipInterval)
        {
            short samp = playWave->theData[m];
            CGRect theRect = {{n*300.0/pointsCycle-2, samp/256.0+125.0-2}, {4,4}};
            CGContextFillEllipseInRect(gc, theRect);
        }
        for (n = 0, m = 2*(7*nSamp/10)+1, first = true; n <= pointsCycle; n++, m+= 2*skipInterval)
        {
            short samp = playWave->theData[m];
            CGRect theRect = {{n*300.0/pointsCycle-2, samp/256.0+125.0-2}, {4,4}};
            CGContextFillEllipseInRect(gc, theRect);
        }
    }
    
    // draw response data, if any
    if (recWave)
    {
        // draw lines between samples
        CGContextSetStrokeColorWithColor(gc, [UIColor greenColor].CGColor);
        for (n = 0, m = 2*(3*nSamp/10), first = true; n <= pointsCycle; n++, m+= 2*skipInterval)
        {
            short samp = recWave->theData[m];
            if (first)
            {
                first = false;
                CGContextMoveToPoint(gc, 0.0, samp/256.0+125.0);
            }
            else
            {
                CGContextAddLineToPoint(gc, n*300.0/pointsCycle, samp/256.0+125.0);
            }
        }
        CGContextStrokePath(gc);
        for (n = 0, m = 2*(7*nSamp/10)+1, first = true; n <= pointsCycle; n++, m+= 2*skipInterval)
        {
            short samp = recWave->theData[m];
            if (first)
            {
                first = false;
                CGContextMoveToPoint(gc, 0.0, samp/256.0+125.0);
            }
            else
            {
                CGContextAddLineToPoint(gc, n*300.0/pointsCycle, samp/256.0+125.0);
            }
        }
        CGContextStrokePath(gc);
        
        // draw dots on top of samples
        CGContextSetFillColorWithColor(gc, [UIColor greenColor].CGColor);
        for (n = 0, m = 2*(3*nSamp/10), first = true; n <= pointsCycle; n++, m+= 2*skipInterval)
        {
            short samp = recWave->theData[m];
            CGRect theRect = {{n*300.0/pointsCycle-2, samp/256.0+125.0-2}, {4,4}};
            CGContextFillEllipseInRect(gc, theRect);
        }
        for (n = 0, m = 2*(7*nSamp/10)+1, first = true; n <= pointsCycle; n++, m+= 2*skipInterval)
        {
            short samp = recWave->theData[m];
            CGRect theRect = {{n*300.0/pointsCycle-2, samp/256.0+125.0-2}, {4,4}};
            CGContextFillEllipseInRect(gc, theRect);
        }
    }
}


@end
