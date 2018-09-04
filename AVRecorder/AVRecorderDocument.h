#import <Cocoa/Cocoa.h>
#import "WaveformView.h"

@class AVCaptureVideoPreviewLayer;
@class AVCaptureSession;
@class AVCaptureDeviceInput;
@class AVCaptureMovieFileOutput;
@class AVCaptureAudioPreviewOutput;
@class AVCaptureConnection;
@class AVCaptureDevice;
@class AVCaptureDeviceFormat;
@class AVFrameRateRange;

@class AVRecorderDocument;
@interface CustomTextField : NSTextField
@property(strong) AVRecorderDocument *doc;
@end

@interface AVRecorderDocument : NSDocument
{
@private
	NSView						*previewView;
	AVCaptureVideoPreviewLayer	*previewLayer;
	NSLevelIndicator			*audioLevelMeterL;
	NSLevelIndicator			*audioLevelMeterR;
	
	AVCaptureSession			*session;
	AVCaptureDeviceInput		*videoDeviceInput;
	AVCaptureDeviceInput		*audioDeviceInput;
	AVCaptureMovieFileOutput	*movieFileOutput;
	AVCaptureAudioPreviewOutput	*audioPreviewOutput;
	
	NSArray						*videoDevices;
	NSArray						*audioDevices;
	
	NSTimer						*audioLevelTimer;
	
	NSArray						*observers;
}

#pragma mark Device Selection
@property (retain) NSArray *videoDevices;
@property (retain) NSArray *audioDevices;
@property (assign) AVCaptureDevice *selectedVideoDevice;
@property (assign) AVCaptureDevice *selectedAudioDevice;

#pragma mark - Device Properties
@property (assign) AVCaptureDeviceFormat *videoDeviceFormat;
@property (assign) AVCaptureDeviceFormat *audioDeviceFormat;
@property (assign) AVFrameRateRange *frameRateRange;
- (IBAction)lockVideoDeviceForConfiguration:(id)sender;

#pragma mark - Recording
@property (retain) AVCaptureSession *session;
@property (readonly) NSArray *availableSessionPresets;
@property (readonly) BOOL hasRecordingDevice;
@property (assign,getter=isRecording) BOOL recording;
@property (assign) IBOutlet NSButton *recordButton;
@property (assign) IBOutlet NSTextField *timestampLabel;

#pragma mark - Preview
@property (assign) IBOutlet NSView *previewView;
@property (assign) float previewVolume;

@property (assign) IBOutlet NSLevelIndicator *audioLevelMeterL;
@property (assign) IBOutlet NSTextField      *audioLevelL;
@property (assign) IBOutlet CustomTextField      *audioPeakL;
@property (assign) IBOutlet WaveformView      *audioWaveformL;

@property (assign) IBOutlet NSLevelIndicator *audioLevelMeterR;
@property (assign) IBOutlet NSTextField      *audioLevelR;
@property (assign) IBOutlet CustomTextField      *audioPeakR;
@property (assign) IBOutlet WaveformView      *audioWaveformR;

#pragma mark - Transport Controls
@property (readonly,getter=isPlaying) BOOL playing;
@property (readonly,getter=isRewinding) BOOL rewinding;
@property (readonly,getter=isFastForwarding) BOOL fastForwarding;
- (IBAction)stop:(id)sender;

@end
