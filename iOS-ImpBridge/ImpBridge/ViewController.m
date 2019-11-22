//
//  ViewController.m
//  ImpBridge
//
//  Created by Mark Williamsen on 5/17/15.
//  for talk #61 given April 25, 2016 at SDiOS.
//  You may use this code however you like,
//  but realize that the burden of verification
//  and validation rests with you alone.
//  http://www.williamsonic.com
//  http://www.sdios.org
//

#import <complex.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <ifaddrs.h>

#import "PlotView.h"
#import "waveFile.h"
#import "ViewController.h"
#import "AppDelegate.h"

@interface ViewController ()

@end

@implementation ViewController

// properties (instance members) of the view
@synthesize playData;
@synthesize recordData;
@synthesize thePlayer;
@synthesize theRecorder;
@synthesize theSettings;

// define local variables
bool sockValid = false;
char sockBuff[1024] = {0};
struct sockaddr_in srcAddr = {0};
struct sockaddr *const pAddr = (struct sockaddr *) &srcAddr;
socklen_t addrLen = 0;
dispatch_source_t theSource = 0;
int theSocket = 0;
int theCount = 0;
NSMutableDictionary *theState = nil;
NSTimeInterval recordTimeNow = 0;
NSTimeInterval playTimeNow = 0;
NSURL *docsURL = nil;

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Do any additional setup after loading the view, typically from a nib.
    thePlayer = nil;
    theRecorder = nil;
    docsURL = [[[NSFileManager defaultManager]
                URLsForDirectory:NSDocumentDirectory
                inDomains:NSUserDomainMask] lastObject];
    [self configureAudio];
    [self checkDetails];
    
    // start datalog file
    NSString *heading = [NSString stringWithCString: logHeading() encoding: NSASCIIStringEncoding];
    NSString *logFilePath = [docsURL.path stringByAppendingPathComponent:@"logFile.csv"];
    NSError *theError = nil;
    [heading writeToFile:logFilePath
                    atomically:NO
                      encoding:NSStringEncodingConversionAllowLossy
                         error:&theError];
    [self openSocket];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
    theSettings = nil;
    playData    = nil;
    recordData  = nil;
}

- (IBAction)handleRec5Button:(id)sender {
    NSLog(@"handleRec5Button");
    theCount = 5;
    rec5Button.enabled = NO;
    rec5Button.alpha = 0.6;
    [self performSelectorOnMainThread:@selector(handleRecordButton:)
                           withObject:nil waitUntilDone:NO];
}

// play sound without recording
- (IBAction)handlePlayButton:(id)sender {
    if (!thePlayer) {return;}
    playTimeNow = thePlayer.deviceCurrentTime;
    BOOL playing = [thePlayer play];
    playButton.enabled = NO;
    playButton.alpha = 0.6;
    NSLog(@"playing: %@, time: %lf", playing? @"YES": @"NO", playTimeNow);
}

// play and record simultaneously
- (IBAction)handleRecordButton:(id)sender {
    theCount--;
    if (!thePlayer) {return;}
    if (!theRecorder) {return;}
    
    BOOL playPrepared = [thePlayer play];
    [thePlayer pause];
    thePlayer.currentTime = 0.0;
    
    BOOL recPrepared = [theRecorder prepareToRecord];
    playButton.enabled = NO;
    recordButton.enabled = NO;
    playButton.alpha = 0.6;
    recordButton.alpha = 0.6;

    playTimeNow = thePlayer.deviceCurrentTime + 0.030;
    recordTimeNow = theRecorder.deviceCurrentTime + 0.030;
    BOOL recording = [theRecorder recordAtTime: recordTimeNow forDuration: 0.500];
    BOOL playing = [thePlayer playAtTime: playTimeNow];
    
    NSLog(@"time: %lf, playing: %@, playPrepared: %@", playTimeNow,
          playing? @"YES": @"NO", playPrepared? @"YES": @"NO");
    NSLog(@"time: %lf, recording: %@, recPrepared: %@", recordTimeNow,
          recording? @"YES": @"NO", recPrepared? @"YES": @"NO");
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    NSTimeInterval playStopped = player.deviceCurrentTime;
    NSLog(@"done playing: %@, delta: %lf", flag? @"YES": @"NO", playStopped - playTimeNow);
    playButton.enabled = YES;
    playButton.alpha = 1.0;
}

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag
{
    NSError *theError = nil;
    NSTimeInterval recStopped = recorder.deviceCurrentTime;
    NSLog(@"done recording: %@, delta: %lf", flag? @"YES": @"NO", recStopped - recordTimeNow);
    if (flag)
    {
        // handle success case
        if (recordData) {recordData = nil;}
        recordData = [[NSData alloc] initWithContentsOfURL:recorder.url];
        [self checkBuffer: recordData.bytes];
        const struct waveFile *theWave = recordData.bytes;
        analyzeWave(theWave);
        
        // display results to user
        NSString *result = [NSString stringWithCString:getResult() encoding:NSASCIIStringEncoding];
        AVAudioSession *theSession = [AVAudioSession sharedInstance];
        float theVolume = [theSession outputVolume];
        float theGain = [theSession inputGain];
        NSString *resultX = [NSString stringWithFormat:@"%@, outputVolume: %f,\ninputGain: %f",
                             result, theVolume, theGain];
        NSLog(@"%@", resultX);
        theText.text = resultX;
        
        // append results to disk log file
        result = [NSString stringWithCString: logResult() encoding:NSASCIIStringEncoding];
        NSString *logFilePath = [docsURL.path stringByAppendingPathComponent:@"logFile.csv"];
        NSFileHandle *logFileHandle = [NSFileHandle fileHandleForWritingAtPath: logFilePath];
        if (logFileHandle)
        {
            [logFileHandle seekToEndOfFile];
            [logFileHandle writeData:[result dataUsingEncoding:NSASCIIStringEncoding]];
            [logFileHandle closeFile];
        }
        
        // continue until done
        if (0 < theCount)
        {
            [self performSelectorOnMainThread:@selector(handleRecordButton:)
                                   withObject:nil waitUntilDone:NO];
        }
        else
        {
            rec5Button.enabled = YES;
            rec5Button.alpha = 1.0;
        }
    }
    
    [thePlot setNeedsDisplay];
    recordButton.enabled = YES;
    recordButton.alpha = 1.0;
    if (flag && theState && sockValid)
    {
        // obtain JSON text for reply
        updateClientState ();
        const char *jsonText = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:theState
                            options:0 error:&theError];
        if (jsonData)
        {
            NSString *theString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]; 
            jsonText = [theString UTF8String];    
        }
        else
        {
            jsonText = "Failed to serialize JSON text for client: %@", [theError localizedDescription];
        }

        // send reply
        if (jsonText)
        {
            ssize_t sendSize = sendto(theSocket, jsonText, strlen(jsonText), 0, pAddr, addrLen);
            NSLog(@"sendSize: %ld", sendSize);
        }
        else
        {
            NSLog(@"Failed to obtain JSON text for client!");
        }
        sockValid = false;
    }
}

- (void)remoteEvent:(UIEvent *)event
{
    if (thePlayer.playing || theRecorder.recording)
    {
        NSString *str = [NSString stringWithFormat:
                         @"remoteEvent type: %d, subtype: %d\n play: %f, record: %f",
                         (int)event.type, (int)event.subtype,
                         thePlayer.currentTime, theRecorder.currentTime];
        NSLog(@"%@", str);
        theText.text = str;    }
    else
    {
        [self performSelectorOnMainThread:@selector(handleRecordButton:)
                               withObject:nil waitUntilDone:NO];
    }

}

// check audio playback buffer contents
- (void) checkBuffer: (const struct waveFile *) aWave
{
    if (!aWave)
    {
        NSLog(@"no buffer to check.");
        return;
    }
    
    NSLog(@"riffID: %.4s\n"
        "riffSize: %d\n"
        "fmtID: %.4s\n"
        "fmtSize: %d\n"
        "fmtCode: %d\n"
        "numChan: %d\n"
        "sampRate: %d\n"
        "byteRate: %d\n"
        "blockAlign: %d\n"
        "bitsSamp: %d\n"
        "fillerID: %.4s\n"
        "fillerSize: %d\n"
        "dataID: %.4s\n"
        "dataSize: %d\n",
        
        aWave->riffHead.chunkID,
        aWave->riffHead.chunkSize,
        aWave->fmtHead.chunkID,
        aWave->fmtHead.chunkSize,
        aWave->fmtCode,
        aWave->numChan,
        aWave->sampRate,
        aWave->byteRate,
        aWave->blockAlign,
        aWave->bitsSamp,
        aWave->fllrHead.chunkID,
        aWave->fllrHead.chunkSize,
        aWave->dataHead.chunkID,
        aWave->dataHead.chunkSize);
}

- (void) checkDetails
{
    AVAudioSession *theSession = [AVAudioSession sharedInstance];
    
    NSString *theCategory = [theSession category];
    AVAudioSessionCategoryOptions theOptions = [theSession categoryOptions];
    float theVolume = [theSession outputVolume];
    float theGain = [theSession inputGain];
    BOOL gainSettable = [theSession isInputGainSettable];
    NSTimeInterval inputLatency = [theSession inputLatency];
    NSTimeInterval outputLatency = [theSession outputLatency];
    double sampleRate = [theSession sampleRate];
    double preferredRate = [theSession preferredSampleRate];
    NSTimeInterval buffDuration = [theSession IOBufferDuration];
    NSString *theMode = [theSession mode];
    NSTimeInterval preferredDuration = [theSession preferredIOBufferDuration];
    NSInteger inputCount = [theSession inputNumberOfChannels];
    NSInteger outputCount = [theSession outputNumberOfChannels];
    BOOL inputAvail = [theSession isInputAvailable];
    BOOL otherAudio = [theSession isOtherAudioPlaying];
    AVAudioSessionRouteDescription *currentRoute = [theSession currentRoute];
    NSUInteger currentInputs = [[currentRoute inputs] count];
    NSUInteger currentOutputs = [[currentRoute outputs] count];
    NSString *theDevices = (NSString *)[AVCaptureDevice devices];
    NSUInteger recLength = 0;
    if (recordData) {recLength = recordData.length;}
    NSString *detailsString = [NSString stringWithFormat:@
                               "theCategory: %@\n"
                               "theOptions: %d\n"
                               "theMode: %@\n"
                               "theVolume: %f\n"
                               "theGain: %f\n"
                               "gainSettable: %@\n"
                               "inputLatency: %f\n"
                               "outputLatency: %f\n"
                               "sampleRate: %lf\n"
                               "preferredRate: %lf\n"
                               "buffDuration: %f\n"
                               "preferredDuration: %f\n"
                               "inputCount: %d\n"
                               "outputCount: %d\n"
                               "inputAvail: %@\n"
                               "otherAudio: %@\n"
                               "currentInputs: %d\n"
                               "currentOutputs: %d\n"
                               "devices: %@\n"
                               "recLength: %d\n",
                               
                               theCategory,
                               (unsigned int)theOptions,
                               theMode,
                               theVolume,
                               theGain,
                               gainSettable? @"YES": @"NO",
                               inputLatency,
                               outputLatency,
                               sampleRate,
                               preferredRate,
                               buffDuration,
                               preferredDuration,
                               (int)inputCount,
                               (int)outputCount,
                               inputAvail? @"YES": @"NO",
                               otherAudio? @"YES": @"NO",
                               (unsigned int)currentInputs,
                               (unsigned int)currentOutputs,
                               theDevices,
                               (unsigned int)recLength];
    NSLog(@"%@", detailsString);
    
    // open text file in my documents directory
    NSString *filePath = [docsURL.path stringByAppendingPathComponent:@"details.txt"];
    NSError *theError = nil;
    [detailsString writeToFile:filePath
                    atomically:NO
                      encoding:NSStringEncodingConversionAllowLossy
                         error:&theError];
}

// receive commands from socket clients
void sockEventHandler(ViewController *theView)
{
    addrLen = sizeof(srcAddr);
    memset(sockBuff, 0, sizeof(sockBuff));
    ssize_t recvSize = recvfrom(theSocket, sockBuff, sizeof(sockBuff), 0, pAddr, &addrLen);
    NSLog(@"sockEventHandler: %d, recvSize: %ld", theSocket, recvSize);
    if (0 >= recvSize)
    {
        sockValid = false;
        return;
    }
    NSLog(@"sockBuff: %s", sockBuff);
    
    // try to parse command as JSON text
    NSError *theError;
    NSString *theString = [[NSString alloc] initWithUTF8String: sockBuff];
    NSData *data = [theString dataUsingEncoding:NSUTF8StringEncoding];
    theState = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&theError];
    
    // read back result and compare
    if (theState)
    {
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:theState options:0 error:&theError];
        theString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        NSLog(@"theState: %@", theString);
    }
    else if (theError)
    {
        // reply with welcome to visitors
        NSString *failStr = [NSString stringWithFormat:@"Welcome to SDiOS SIG #61\n"
                             "Using External Sensors with iOS Handheld Apps\n"
                             "%@", theString];
        
        // TODO NSString *failStr = [NSString stringWithFormat:@"Failed to parse command: %@",
        //                      [theError localizedDescription]];
        NSLog(@"%@", failStr);
        const char *failText = [failStr UTF8String];
        ssize_t sendSize = sendto(theSocket, failText, strlen(failText), 0, pAddr, addrLen);
        NSLog(@"sendSize: %ld", sendSize);
        sockValid = false;
        return;
    }
    
    // report command source, run measurement
    char srcStr[INET_ADDRSTRLEN] = {0};
    inet_ntop(AF_INET, &srcAddr.sin_addr, srcStr, INET_ADDRSTRLEN);
    NSLog(@"srcPort: %d, srcHost: %s", ntohs(srcAddr.sin_port), srcStr);
    
    // be sure we aren't busy
    if (sockValid || (0 < theCount))
    {
        // tell client we are busy right now
        char *failText = "{\"fail\":\"Server is busy!\"}";
        ssize_t sendSize = sendto(theSocket, failText, strlen(failText), 0, pAddr, addrLen);
        NSLog(@"Server busy, sendSize: %ld", sendSize);
    }
    else
    {
        // trigger a measurement
        sockValid = true;
        updateServerState(theView);
        [theView performSelectorOnMainThread:@selector(handleRecordButton:)
                                  withObject:nil waitUntilDone:NO];
    }
}

void sockCancelHandler(ViewController *theView)
{
    NSLog(@"sockCancelHandler: %d", theSocket);
}

- (void) closeSocket
{
    // dispose of source and socket (TN2277)
    dispatch_source_cancel(theSource);
    close(theSocket);
    sockValid = false;
}

- (void) openSocket
{
    // configure and open user datagram protocol (UDP) socket
    theSocket = socket(PF_INET, SOCK_DGRAM, IPPROTO_UDP);  // IPv4, returns descriptor, or -1 if error
    NSLog(@"theSocket: %d", theSocket);
    struct sockaddr_in theSockaddr = {0};
    struct sockaddr *sockaddrPtr = (struct sockaddr *)&theSockaddr;
    int thePton = inet_pton(AF_INET, "0.0.0.0", &theSockaddr.sin_addr);  // returns 1 on success, 0 if invalid, -1 if error
    NSLog(@"thePton: %d", thePton);
    const int thePort = 54321;
    theSockaddr.sin_port = htons(thePort);
    int theBind = bind(theSocket, sockaddrPtr, sizeof(theSockaddr));  // returns 0 on success, -1 if error
    if (theBind < 0)
    {
        NSLog(@"theBind: %d, theError: %d", theBind, errno);
    }
    else
    {
        NSLog(@"theBind: %d", theBind);
    }
    
    // try to get WiFi IP address
    struct ifaddrs *theAddrs = NULL;
    struct ifaddrs *theAddr = NULL;
    int rslt = getifaddrs(&theAddrs);
    if (!rslt && theAddrs)
    {
        NSString *addrList = [NSString stringWithFormat:@"Network Addresses for port: %d", thePort];
        for (theAddr = theAddrs; theAddr; theAddr = theAddr->ifa_next)
        {
            NSString *nameStr = [NSString stringWithUTF8String:theAddr->ifa_name];
            NSString *addrStr = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)theAddr->ifa_addr)->sin_addr)];
            if (![addrStr isEqualToString:@"0.0.0.0"])
            {
                addrList = [addrList stringByAppendingFormat:@"\nname: %@, addr: %@", nameStr, addrStr];
            }
        }
        NSLog(@"%@", addrList);
        theText.text = addrList;
    }
    
    // use grand central dispatch (GCD) to respond to socket requests
    theSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, theSocket, 0, dispatch_get_global_queue(0, 0));
    dispatch_source_set_event_handler(theSource, ^{sockEventHandler(self);});
    dispatch_source_set_cancel_handler(theSource, ^{sockCancelHandler(self);});
    dispatch_resume(theSource);
}

- (void) configureAudio
{
    // configure audio session
    NSError *theError = nil;
    AVAudioSession *theSession = [AVAudioSession sharedInstance];
    BOOL categorySet = [theSession setCategory:AVAudioSessionCategoryPlayAndRecord error:&theError];
    BOOL rateSet = [theSession setPreferredSampleRate:44100.0 error:&theError];
    BOOL activeSet = [theSession setActive:YES error:&theError];
    BOOL gainSet = [theSession setInputGain:0.5 error:&theError];
    if (theError) {NSLog(@"Failed to set session properties: %@", [theError localizedDescription]);}
    NSLog(@"configure session: %@, %@, %@, %@", categorySet? @"YES": @"NO",
          rateSet? @"YES": @"NO", gainSet? @"YES": @"NO", activeSet? @"YES": @"NO");
    
    // configure player settings
    theSettings = [[NSDictionary alloc] initWithObjectsAndKeys:
                   [NSNumber numberWithFloat:44100.0], AVSampleRateKey,
                   [NSNumber numberWithInt:kAudioFormatLinearPCM], AVFormatIDKey,
                   [NSNumber numberWithInt: 2], AVNumberOfChannelsKey,
                   [NSNumber numberWithInt: 16], AVLinearPCMBitDepthKey,
                   NO, AVLinearPCMIsBigEndianKey,
                   NO, AVLinearPCMIsFloatKey,
                   NO, AVLinearPCMIsNonInterleaved, nil];
    
    // populate RAM buffer with wave data
    if (playData) {playData = nil;}
    playData = [[NSMutableData alloc] initWithLength:(nSamp * 4) + 4096];
    struct waveFile *theWave = playData.mutableBytes;
    setSize(theWave, nSamp);
    NSLog(@"sizeof(theWave): %ld", sizeof(struct waveFile));
    fillWave(theWave);
    [self checkBuffer: theWave];
    
    // write wave data to file
    NSString *playFilePath = [docsURL.path stringByAppendingPathComponent:@"play.wav"];
    [playData writeToFile:playFilePath atomically:NO];
    NSLog(@"play path: %@", playFilePath);
    
    // configure player with data in file
    NSURL *playURL = [[NSURL alloc] initFileURLWithPath:playFilePath];
    thePlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:playURL error:&theError];
    if (theError || !thePlayer)
    {
        NSLog(@"Failed to initialize player: %@", [theError localizedDescription]);
        return;
    }
    
    thePlayer.delegate = self;
    BOOL playPrepared = [thePlayer prepareToPlay];
    NSLog(@"player prepared: %@", playPrepared? @"YES": @"NO");
    NSLog(@"player settings: %@", [thePlayer.settings descriptionInStringsFileFormat]);
    
    // delete existing wave file
    NSString *recFilePath = [docsURL.path stringByAppendingPathComponent:@"record.wav"];
    NSLog(@"record path: %@", recFilePath);
    NSFileManager *fileMgr = [NSFileManager defaultManager];
    theError = nil;
    if ([fileMgr removeItemAtPath:recFilePath error:&theError])
    {NSLog(@"deleted wave file.");} else {NSLog(@"nothing to delete.");}
    
    // intialize recorder
    NSURL *recordURL = [[NSURL alloc] initFileURLWithPath:recFilePath];
    theRecorder = [[AVAudioRecorder alloc] initWithURL:recordURL
                                              settings:theSettings
                                                 error:&theError];
    if (theError || !theRecorder)
    {
        NSLog(@"Failed to intialize recorder: %@", [theError localizedDescription]);
        return;
    }
    
    theRecorder.delegate = self;
    BOOL recPrepared = [theRecorder prepareToRecord];
    NSLog(@"recorder prepared: %@", recPrepared? @"YES": @"NO");
    NSLog(@"recorder settings: %@", [theRecorder.settings descriptionInStringsFileFormat]);
    
    // ok to receive remote control events
    UIApplication *theApp = [UIApplication sharedApplication];
    AppDelegate *theDelegate = [theApp delegate];
    theDelegate.theView = self;
    thePlot.theView = self;
    [theApp beginReceivingRemoteControlEvents];
}

// helper function to get complex values from state tree
complex double getComplexValue(NSArray *cplx)
{
    return[[cplx objectAtIndex:0] doubleValue] + [[cplx objectAtIndex:1] doubleValue] * I;
}

void updateServerState(ViewController *theView)
{
    complex double e1, e2, e1p, e2p;
    int freq = 0, seq = 0;
    
    if (theState)
    {
        // gather up needed parameters, assumes fixed format tree
        NSArray *meas = [theState objectForKey:@"meas"];
        e1  = getComplexValue([[meas objectAtIndex:0] objectForKey:@"left"]);
        e2  = getComplexValue([[meas objectAtIndex:0] objectForKey:@"right"]);
        e1p = getComplexValue([[meas objectAtIndex:1] objectForKey:@"left"]);
        e2p = getComplexValue([[meas objectAtIndex:1] objectForKey:@"right"]);
        freq = [[theState objectForKey:@"freq"] intValue];
        seq  = [[theState objectForKey:@"seq"]  intValue];
        
        // modify RAM buffer with new wave data
        setParams(e1, e2, e1p, e2p, freq);
        if (!theView.playData) {theView.playData = [[NSMutableData alloc] initWithLength:(nSamp * 4) + 4096];}
        struct waveFile *theWave = theView.playData.mutableBytes;
        fillWave(theWave);
        [theView checkBuffer: theWave];
        
        // write wave data to file, with new frequency and amplitude
        NSString *playFilePath = [docsURL.path stringByAppendingPathComponent:@"play.wav"];
        [theView.playData writeToFile:playFilePath atomically:NO];
        NSLog(@"play path: %@", playFilePath);
    }
}

void updateClientState()
{
    complex double e3, e3p, e4, e4p;
    
    getParams(&e3, &e3p, &e4, &e4p);
    NSArray *micFirst = [NSArray arrayWithObjects:[NSNumber numberWithDouble:creal(e3)],
                         [NSNumber numberWithDouble:cimag(e3)], nil];
    NSArray *micSecond = [NSArray arrayWithObjects:[NSNumber numberWithDouble:creal(e3p)],
                          [NSNumber numberWithDouble:cimag(e3p)], nil];
    NSArray *bkgFirst = [NSArray arrayWithObjects:[NSNumber numberWithDouble:creal(e4)],
                         [NSNumber numberWithDouble:cimag(e4)], nil];
    NSArray *bkgSecond = [NSArray arrayWithObjects:[NSNumber numberWithDouble:creal(e4p)],
                          [NSNumber numberWithDouble:cimag(e4p)], nil];
    if (theState)
    {
        // distribute needed parameters, assumes fixed format tree
        NSMutableDictionary *chan;
        chan = [[theState objectForKey:@"meas"] objectAtIndex:0];
        [chan setValue:micFirst forKey:@"mic"];
        [chan setValue:bkgFirst forKey:@"bkg"];
        chan = [[theState objectForKey:@"meas"] objectAtIndex:1];
        [chan setValue:micSecond forKey:@"mic"];
        [chan setValue:bkgSecond forKey:@"bkg"];
    }
}

@end
