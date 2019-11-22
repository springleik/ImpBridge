//
//  ViewController.h
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

@class PlotView;

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

@interface ViewController : UIViewController <AVAudioPlayerDelegate, AVAudioRecorderDelegate>
{
    IBOutlet UIButton *rec5Button;
    IBOutlet UIButton *playButton;
    IBOutlet UIButton *recordButton;
    IBOutlet UITextView *theText;
    IBOutlet PlotView *thePlot;
}

@property (nonatomic, retain) NSMutableData *playData;
@property (nonatomic, retain) NSData *recordData;
@property (nonatomic, retain) AVAudioPlayer *thePlayer;
@property (nonatomic, retain) AVAudioRecorder *theRecorder;
@property (nonatomic, retain) NSDictionary *theSettings;

- (IBAction)handleRec5Button:(id)sender;
- (IBAction)handlePlayButton:(id)sender;
- (IBAction)handleRecordButton:(id)sender;

- (void) remoteEvent:(UIEvent *)event;
- (void) checkBuffer: (const struct waveFile *) aWave;
- (void) checkDetails;
- (void) closeSocket;
- (void) openSocket;
- (void) configureAudio;

void updateClientState();
void updateServerState(ViewController *);

@end

