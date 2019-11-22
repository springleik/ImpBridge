//
//  ImpAppDelegate.h
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

#import <Cocoa/Cocoa.h>

@interface ImpAppDelegate : NSObject <NSApplicationDelegate>
{
    NSWindow *_window;
    NSTextField *_freqField;
    NSTextField *_leftField;
    NSTextField *_rightField;
    NSTextField *_hostField;
    NSTextField *_portField;
    NSTextField *_replyField;
    NSButton *_contButton;
    NSButton *_levlButton;
    NSTextField *_realLeftField;
    NSTextField *_imagLeftField;
    NSTextField *_realRightField;
    NSTextField *_imagRightField;
    NSSegmentedControl *_refSegment;
}

@property (assign) IBOutlet NSWindow *window;
@property (assign) IBOutlet NSTextField *freqField;
@property (assign) IBOutlet NSTextField *leftField;
@property (assign) IBOutlet NSTextField *rightField;
@property (assign) IBOutlet NSTextField *hostField;
@property (assign) IBOutlet NSTextField *portField;
@property (assign) IBOutlet NSTextField *replyField;
@property (assign) IBOutlet NSButton *contButton;
@property (assign) IBOutlet NSButton *levlButton;
@property (assign) IBOutlet NSTextField *realLeftField;
@property (assign) IBOutlet NSTextField *imagLeftField;
@property (assign) IBOutlet NSTextField *realRightField;
@property (assign) IBOutlet NSTextField *imagRightField;
@property (assign) IBOutlet NSSegmentedControl *refSegment;

- (IBAction) measButton:(id)sender;
- (IBAction) contChkBox:(id)sender;
- (IBAction) levlChkBox:(id)sender;
- (IBAction) refSegCtrl:(id)sender;

- (void) openSocket;
- (void) closeSocket;

@end

void sockEventHandler(ImpAppDelegate *);
void sockCancelHandler(ImpAppDelegate *);
complex double parseCplxDbl(char *);

// helper macro to parse complex values from JSON
#define realImag(A) creal(A), cimag(A)
