//
//  ImpAppDelegate.m
//  ImpBridge
//
//  Created by Mark Williamsen on 4/17/16.
//  for talk #61 given April 25, 2016 at SDiOS.
//  You may use this code however you like,
//  but realize that the burden of verification
//  and validation rests with you alone.
//  http://www.williamsonic.com
//  http://www.sdios.org
//

#include <complex.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <ifaddrs.h>

#import "ImpAppDelegate.h"

@implementation ImpAppDelegate

@synthesize window = _window;
@synthesize freqField = _freqField;
@synthesize leftField = _leftField;
@synthesize rightField = _rightField;
@synthesize hostField = _hostField;
@synthesize portField = _portField;
@synthesize replyField = _replyField;
@synthesize contButton = _contButton;
@synthesize levlButton = _levlButton;
@synthesize realLeftField = _realLeftField;
@synthesize imagLeftField = _imagLeftField;
@synthesize realRightField = _realRightField;
@synthesize imagRightField = _imagRightField;
@synthesize refSegment = _refSegment;

NSString *jsonString = nil;
NSString *hostString = nil;
NSInteger rightInteger = 0;
NSInteger freqInteger = 0;
NSInteger leftInteger = 0;
NSInteger portInteger = 0;
NSInteger seqInteger = 0;
int theSocket = 0;
dispatch_source_t theSource = 0;
char writeBuff[1024] = {0};
char readBuff[1024] = {0};

NSString *logFilePath = @"/Users/YourNameHere/Documents";

- (void) dealloc
{
    [super dealloc];
}
	
- (void) applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
    // create new empty log file in Documents directory, erasing previous
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if ([paths count]) {logFilePath = [paths objectAtIndex:0];}
    logFilePath = [[logFilePath stringByAppendingPathComponent:@"ImpBridge.csv"] retain];
    NSString *headerStr = @"e1,e2,e3,e4,e1p,e2p,e3p,e4p,zR\n";
    [[NSFileManager defaultManager] createFileAtPath:logFilePath contents:[headerStr dataUsingEncoding:NSUTF8StringEncoding] attributes:nil];
}

// obtain real and imaginary values from comma-separated text string
complex double parseCplxDbl(char *p)
{
    double real = 0.0, imag = 0.0;
    sscanf(p, "%lf,%lf", &real, &imag);
    return real + (imag * I);
}

complex double
    e1 = 0.0,       // first left drive amplitude
    e2 = 0.0,       // first right drive amlitude
    e3 = 0.0,       // first measured response
    e4 = 0.0,       // first measured background
    e1p = 0.0,      // second left drive amplitude
    e2p = 0.0,      // second right drive amlitude
    e3p = 0.0,      // second measured response
    e4p = 0.0,      // second measured background
    zLeft = 0.0,    // first impedance
    zRight = 0.0,   // second impedance
    zRatio = 0.0;   // impedance ratio zLeft/zRight

// process replies received from measurement server
void sockEventHandler(ImpAppDelegate *theDelegate)
{
    //read reply from server   
    NSLog(@"sockEventHandler");
    struct sockaddr_in theSockaddr = {0};
    struct sockaddr *sockaddrPtr = (struct sockaddr *) &theSockaddr;
    uint addrLen = sizeof(theSockaddr);
    memset(readBuff, 0, sizeof(readBuff));  // start with clean buffer
    ssize_t readSize = recvfrom(theSocket, readBuff, sizeof(readBuff), 0, sockaddrPtr, &addrLen);
    NSLog(@"readSize: %ld", readSize);
    NSLog(@"reply: %s", readBuff);
    readBuff[1023] = '\0';  // force trailing null, just in case
    
    // copy reply into text field
    theDelegate.replyField.stringValue = [NSString stringWithCString:readBuff encoding:NSASCIIStringEncoding];
    
    // parse JSON tree to obtain measurement reply, a poor man's JSON parser
    // because NSJSONSerialization class wasn't available until OS X v10.7
    char readCopy[1024] = {0};
    strcpy(readCopy, readBuff);
    char *o = strstr(readCopy, "fail");
    char *p = strstr(readCopy, "meas");
    if (o || !p)
    {
        // error or empty reply received
        [NSThread sleepForTimeInterval:1.0];
        return; // exit early
    }
    
    // parse first measurement
    strcpy(readCopy, readBuff);
    char *q = 1 + strstr(strstr(p, "left"), "[");
    char *r = 1 + strstr(strstr(p, "right"), "[");
    char *s = 1 + strstr(strstr(p, "mic"), "[");
    char *t = 1 + strstr(strstr(p, "bkg"), "[");
    q = strtok(q, "]");
    r = strtok(r, "]");
    s = strtok(s, "]");
    t = strtok(t, "]");
    e1 = parseCplxDbl(q);
    e2 = parseCplxDbl(r);
    e3 = parseCplxDbl(s);
    e4 = parseCplxDbl(t);
    
    // parse second measurement
    strcpy(readCopy, readBuff);
    q = 1 + strstr(strstr(1+strstr(p, "left"), "left"), "[");
    r = 1 + strstr(strstr(1+strstr(p, "right"), "right"), "[");
    s = 1 + strstr(strstr(1+strstr(p, "mic"), "mic"), "[");
    t = 1 + strstr(strstr(1+strstr(p, "bkg"), "bkg"), "[");
    q = strtok(q, "]");
    r = strtok(r, "]");
    s = strtok(s, "]");
    t = strtok(t, "]");
    e1p = parseCplxDbl(q);
    e2p = parseCplxDbl(r);
    e3p = parseCplxDbl(s);
    e4p = parseCplxDbl(t);
    
    // compute impedance ratio = zLeft/zRight
    zRatio = (e1 * e3p - e1p * e3) / (e2p * e3 - e2 * e3p);
    
    // compute unknown impedance using reference value and ratio
    int theSegment = [theDelegate.refSegment selectedSegment];
    double realPart = 1.0;
    double imagPart = 0.0;
    NSString *formatString = @"%.6g";
    switch(theSegment)
    {
        case 0: // left impedance is the reference
            realPart = [theDelegate.realLeftField doubleValue];
            imagPart = [theDelegate.imagLeftField doubleValue];
            zLeft = realPart + imagPart * I;
            zRight = zLeft / zRatio;
            [theDelegate.realRightField setStringValue:[NSString stringWithFormat:formatString, creal(zRight)]];
            [theDelegate.imagRightField setStringValue:[NSString stringWithFormat:formatString, cimag(zRight)]];
            break;
            
        case 1: // right impedance is the reference
            realPart = [theDelegate.realRightField doubleValue];
            imagPart = [theDelegate.imagRightField doubleValue];
            zRight = realPart + imagPart * I;
            zLeft = zRight * zRatio;
            [theDelegate.realLeftField setStringValue:[NSString stringWithFormat:formatString, creal(zLeft)]];
            [theDelegate.imagLeftField setStringValue:[NSString stringWithFormat:formatString, cimag(zLeft)]];
            break;
            
        default:
            NSLog(@"Unexpected segment: %d", theSegment);
            break;
            
    }
    
    // perform leveling on output amplitude
    if ([theDelegate.levlButton state])
    {
        // adjust left drive level to maintain constant input level
        int prevValue = [theDelegate.leftField integerValue];
        int newValue = prevValue;
        double theLevel = cabs(e3);
        if (theLevel > 12000.0) {newValue /= 2;}
        else if (theLevel < 6000.0) {newValue *= 2;}
        newValue = (newValue < 125)? 125: newValue;
        newValue = (newValue > 32000)? 32000: newValue;
        [theDelegate.leftField setIntegerValue:newValue];
        
        // adjust right drive level to maintain constant input level
        prevValue = [theDelegate.rightField integerValue];
        newValue = prevValue;
        theLevel = cabs(e3p);
        if (theLevel > 12000.0) {newValue /= 2;}
        else if (theLevel < 6000.0) {newValue *= 2;}
        newValue = (newValue < 125)? 125: newValue;
        newValue = (newValue > 32000)? 32000: newValue;
        [theDelegate.rightField setIntegerValue:newValue];
    }
    
    // log results
    NSLog(@"e1:  %lf%+lfi\n"
          "e2:  %lf%+lfi\n"
          "e3:  %lf%+lfi\n"
          "e4:  %lf%+lfi\n"
          "e1p: %lf%+lfi\n"
          "e2p: %lf%+lfi\n"
          "e3p: %lf%+lfi\n"
          "e4p: %lf%+lfi\n"
          "zR:  %lf%+lfi\n",
          realImag(e1),
          realImag(e2),
          realImag(e3),
          realImag(e4),
          realImag(e1p),
          realImag(e2p),
          realImag(e3p),
          realImag(e4p),
          realImag(zRatio));
    
    // store results to disk file
    NSString *logString = [NSString stringWithFormat:@"%lf%+lfi,"
                                                    "%lf%+lfi,"
                                                    "%lf%+lfi,"
                                                    "%lf%+lfi,"
                                                    "%lf%+lfi,"
                                                    "%lf%+lfi,"
                                                    "%lf%+lfi,"
                                                    "%lf%+lfi,"
                                                    "%lf%+lfi\n",
                                                    realImag(e1),
                                                    realImag(e2),
                                                    realImag(e3),
                                                    realImag(e4),
                                                    realImag(e1p),
                                                    realImag(e2p),
                                                    realImag(e3p),
                                                    realImag(e4p),
                                                    realImag(zRatio)];
    NSFileHandle *theHandle = [NSFileHandle fileHandleForWritingAtPath:logFilePath];
    if (theHandle)
    {
        [theHandle seekToEndOfFile];
        [theHandle writeData:[logString dataUsingEncoding:NSASCIIStringEncoding]];
        [theHandle closeFile];
    }
    
    // handle continuous measurements
    if ([theDelegate.contButton state])
    {
        [theDelegate performSelectorOnMainThread:@selector(measButton:) withObject:nil waitUntilDone:NO];
    }
}

void sockCancelHandler(ImpAppDelegate *theDelegate)
{
    NSLog(@"sockCancelHandler");
}

// runs once at launch
- (void) openSocket
{
    // create a socket
    theSocket = socket(PF_INET, SOCK_DGRAM, IPPROTO_UDP);  // IPv4, returns descriptor, -1 if error
    NSLog(@"theSocket: %d", theSocket);
    
    // create a dispatch source
    theSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, theSocket, 0, dispatch_get_global_queue(0,0));
    dispatch_source_set_event_handler(theSource, ^{sockEventHandler(self);});
    dispatch_source_set_cancel_handler(theSource, ^{sockCancelHandler(self);});
    dispatch_resume(theSource);
}

// runs once at termination
- (void) closeSocket
{
    NSLog(@"%@", @"Closing socket.");
    if (theSource) {dispatch_source_cancel(theSource); theSource = 0;}
    if (theSocket) {close(theSocket); theSocket = 0;}
}

- (void) applicationWillTerminate:(NSNotification *)aNotification
{
    [self closeSocket];
}

// request a new measurement
- (IBAction) measButton:(id)sender
{
    NSLog(@"Measure button pressed: %d", [sender state]);
    if (!theSocket) {[self openSocket];}
    
    // gather up field data
    freqInteger  = [self.freqField integerValue];
    leftInteger  = [self.leftField integerValue];
    rightInteger = [self.rightField integerValue];
    hostString   = [self.hostField stringValue];
    portInteger  = [self.portField integerValue];
    NSLog(@"Fields: %d, %d, %d, %@, %d", freqInteger, leftInteger, rightInteger, hostString, portInteger);
    
    // build JSON tree as text
    jsonString = [NSString stringWithFormat:@"{\"seq\":%d,\"freq\":%d,\"meas\":"
                  "[{\"left\":[%d,0],\"right\":[0,0]},{\"left\":[0,0],\"right\":[%d,0]}]}",
                  seqInteger,
                  freqInteger,
                  leftInteger,
                  rightInteger];
    NSLog(@"%@", jsonString);
    
    // build socket address
    struct sockaddr_in theSockaddr = {0};
    struct sockaddr *sockaddrPtr = (struct sockaddr *) &theSockaddr;
    int thePton = inet_pton(AF_INET, [hostString UTF8String], &theSockaddr.sin_addr);  
    NSLog(@"thePton: %d", thePton); // returns 1 if ok, 0 invalid, -1 error
    theSockaddr.sin_port = htons((int)portInteger);
    
    // send request to server
    strcpy(writeBuff, [jsonString UTF8String]);
    int rslt = sendto(theSocket, writeBuff, strlen(writeBuff), 0, sockaddrPtr, sizeof(theSockaddr));
    NSLog(@"sendto: %d", rslt);
    seqInteger++;
}

// continuous measurements when checked
- (IBAction) contChkBox:(id)sender
{
    NSLog(@"Continuous: %d", [sender state]);
}

// leveling enabled when checked
- (IBAction) levlChkBox:(id)sender
{
    NSLog(@"Leveling: %d", [sender state]);
}

// user's choice of reference impedance
- (IBAction) refSegCtrl:(id)sender
{
    NSLog(@"Reference: %d", [sender selectedSegment]);
}

@end
