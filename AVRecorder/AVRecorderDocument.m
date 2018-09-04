#import "AVRecorderDocument.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMediaIO/CMIOHardware.h>

@interface AVRecorderDocument () <AVCaptureFileOutputDelegate, AVCaptureFileOutputRecordingDelegate>

// Properties for internal use
@property (retain) AVCaptureDeviceInput *videoDeviceInput;
@property (retain) AVCaptureDeviceInput *audioDeviceInput;
@property (readonly) BOOL selectedVideoDeviceProvidesAudio;
@property (retain) AVCaptureAudioPreviewOutput *audioPreviewOutput;
@property (retain) AVCaptureMovieFileOutput *movieFileOutput;
@property (retain) AVCaptureVideoPreviewLayer *previewLayer;
@property (assign) NSTimer *audioLevelTimer;
@property (retain) NSArray *observers;

// Methods for internal use
- (void)refreshDevices;
- (void)setTransportMode:(AVCaptureDeviceTransportControlsPlaybackMode)playbackMode speed:(AVCaptureDeviceTransportControlsSpeed)speed forDevice:(AVCaptureDevice *)device;

@end

@implementation AVRecorderDocument

@synthesize videoDeviceInput;
@synthesize audioDeviceInput;
@synthesize videoDevices;
@synthesize audioDevices;
@synthesize session;
@synthesize audioLevelMeterL;
@synthesize audioLevelMeterR;
@synthesize audioPreviewOutput;
@synthesize movieFileOutput;
@synthesize previewView;
@synthesize previewLayer;
@synthesize audioLevelTimer;
@synthesize observers;

- (id)init
{
	self = [super init];
	if (self) {
		// Create a capture session
		session = [[AVCaptureSession alloc] init];
		
		// Capture Notification Observers
		NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
		id runtimeErrorObserver = [notificationCenter addObserverForName:AVCaptureSessionRuntimeErrorNotification
																  object:session
																   queue:[NSOperationQueue mainQueue]
															  usingBlock:^(NSNotification *note) {
																  dispatch_async(dispatch_get_main_queue(), ^(void) {
																	  [self presentError:[[note userInfo] objectForKey:AVCaptureSessionErrorKey]];
																  });
															  }];
		id deviceWasConnectedObserver = [notificationCenter addObserverForName:AVCaptureDeviceWasConnectedNotification
																		object:nil
																		 queue:[NSOperationQueue mainQueue]
																	usingBlock:^(NSNotification *note) {
																		[self refreshDevices];
																	}];
		id deviceWasDisconnectedObserver = [notificationCenter addObserverForName:AVCaptureDeviceWasDisconnectedNotification
																		   object:nil
																			queue:[NSOperationQueue mainQueue]
																	   usingBlock:^(NSNotification *note) {
																		   [self refreshDevices];
																	   }];
		observers = [[NSArray alloc] initWithObjects:runtimeErrorObserver, deviceWasConnectedObserver, deviceWasDisconnectedObserver, nil];

		// Attach outputs to session
		movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
		[movieFileOutput setDelegate:self];
		movieFileOutput.movieFragmentInterval = CMTimeMake(10, 1);
		[session addOutput:movieFileOutput];
		
		audioPreviewOutput = [[AVCaptureAudioPreviewOutput alloc] init];
		[audioPreviewOutput setVolume:0.f];
		[session addOutput:audioPreviewOutput];
		
		// Select devices if any exist
		AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
		if (videoDevice) {
			[self setSelectedVideoDevice:videoDevice];
			[self setSelectedAudioDevice:[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio]];
		} else {
			[self setSelectedVideoDevice:[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeMuxed]];
		}
		
		// Initial refresh of device list
		[self refreshDevices];
	}
	return self;
}

- (void)windowWillClose:(NSNotification *)notification
{
	// Invalidate the level meter timer here to avoid a retain cycle
	[[self audioLevelTimer] invalidate];
	
	// Stop the session
	[[self session] stopRunning];
	
	// Set movie file output delegate to nil to avoid a dangling pointer
	[[self movieFileOutput] setDelegate:nil];
	
	// Remove Observers
	NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
	for (id observer in [self observers])
		[notificationCenter removeObserver:observer];
	[observers release];
}

- (void)dealloc
{
	[videoDevices release];
	[audioDevices release];
	[session release];
	[audioPreviewOutput release];
	[movieFileOutput release];
	[previewLayer release];
	[videoDeviceInput release];
	[audioDeviceInput release];
	
	[super dealloc];
}

- (NSString *)windowNibName
{
	return @"AVRecorderDocument";
}

- (void)windowControllerDidLoadNib:(NSWindowController *) aController
{
	[super windowControllerDidLoadNib:aController];
	
	// Attach preview to session
	CALayer *previewViewLayer = [[self previewView] layer];
	[previewViewLayer setBackgroundColor:CGColorGetConstantColor(kCGColorBlack)];
	AVCaptureVideoPreviewLayer *newPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:[self session]];
	[newPreviewLayer setFrame:[previewViewLayer bounds]];
	[newPreviewLayer setAutoresizingMask:kCALayerWidthSizable | kCALayerHeightSizable];
	[previewViewLayer addSublayer:newPreviewLayer];
	[self setPreviewLayer:newPreviewLayer];
	[newPreviewLayer release];
	
	// Start the session
	[[self session] startRunning];
	
	// Start updating the audio level meter
	[self setAudioLevelTimer:[NSTimer scheduledTimerWithTimeInterval:1./10. target:self selector:@selector(updateAudioLevels:) userInfo:nil repeats:YES]];
	[[self audioPeakL] setFloatValue:-99];
	[[self audioPeakR] setFloatValue:-99];
	[self audioPeakL].doc = self;
	[self audioPeakR].doc = self;
}

- (void)didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void  *)contextInfo
{
	// Do nothing
}

#pragma mark - Device selection
- (void)refreshDevices
{
	CMIOObjectPropertyAddress   prop    = {
		kCMIOHardwarePropertyAllowScreenCaptureDevices,
		kCMIOObjectPropertyScopeGlobal,
		kCMIOObjectPropertyElementMaster
	};
	UInt32                      allow   = 1;
	OSStatus ret = CMIOObjectSetPropertyData(kCMIOObjectSystemObject, &prop, 0, NULL, sizeof(allow), &allow);
	if (ret)
		NSLog(@"ret=%d",ret);
	
	
	[self setVideoDevices:[[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] arrayByAddingObjectsFromArray:[AVCaptureDevice devicesWithMediaType:AVMediaTypeMuxed]]];
	[self setAudioDevices:[AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio]];
	
	[[self session] beginConfiguration];
	
	if (![[self videoDevices] containsObject:[self selectedVideoDevice]])
		[self setSelectedVideoDevice:nil];
	
	if (![[self audioDevices] containsObject:[self selectedAudioDevice]])
		[self setSelectedAudioDevice:nil];
	
	[[self session] commitConfiguration];
}

- (AVCaptureDevice *)selectedVideoDevice
{
	return [videoDeviceInput device];
}

- (void)setSelectedVideoDevice:(AVCaptureDevice *)selectedVideoDevice
{
	[[self session] beginConfiguration];
	
	if ([self videoDeviceInput]) {
		// Remove the old device input from the session
		[session removeInput:[self videoDeviceInput]];
		[self setVideoDeviceInput:nil];
	}
	
	if (selectedVideoDevice) {
		NSError *error = nil;
		
		// Create a device input for the device and add it to the session
		AVCaptureDeviceInput *newVideoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:selectedVideoDevice error:&error];
		if (newVideoDeviceInput == nil) {
			dispatch_async(dispatch_get_main_queue(), ^(void) {
				[self presentError:error];
			});
		} else {
			if (![selectedVideoDevice supportsAVCaptureSessionPreset:[session sessionPreset]])
				[[self session] setSessionPreset:AVCaptureSessionPresetHigh];
			
			[[self session] addInput:newVideoDeviceInput];
			[self setVideoDeviceInput:newVideoDeviceInput];
		}
	}
	
	// If this video device also provides audio, don't use another audio device
	if ([self selectedVideoDeviceProvidesAudio])
		[self setSelectedAudioDevice:nil];
	
	[[self session] commitConfiguration];
}

- (AVCaptureDevice *)selectedAudioDevice
{
	return [audioDeviceInput device];
}

- (void)setSelectedAudioDevice:(AVCaptureDevice *)selectedAudioDevice
{
	[[self session] beginConfiguration];
	
	if ([self audioDeviceInput]) {
		// Remove the old device input from the session
		[session removeInput:[self audioDeviceInput]];
		[self setAudioDeviceInput:nil];
	}
	
	if (selectedAudioDevice && ![self selectedVideoDeviceProvidesAudio]) {
		NSError *error = nil;
		
		// Create a device input for the device and add it to the session
		AVCaptureDeviceInput *newAudioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:selectedAudioDevice error:&error];
		if (newAudioDeviceInput == nil) {
			dispatch_async(dispatch_get_main_queue(), ^(void) {
				[self presentError:error];
			});
		} else {
			if (![selectedAudioDevice supportsAVCaptureSessionPreset:[session sessionPreset]])
				[[self session] setSessionPreset:AVCaptureSessionPresetHigh];
			
			[[self session] addInput:newAudioDeviceInput];
			[self setAudioDeviceInput:newAudioDeviceInput];
		}
	}
	
	[[self session] commitConfiguration];
}

#pragma mark - Device Properties

+ (NSSet *)keyPathsForValuesAffectingSelectedVideoDeviceProvidesAudio
{
	return [NSSet setWithObjects:@"selectedVideoDevice", nil];
}

- (BOOL)selectedVideoDeviceProvidesAudio
{
	return ([[self selectedVideoDevice] hasMediaType:AVMediaTypeMuxed] || [[self selectedVideoDevice] hasMediaType:AVMediaTypeAudio]);
}

+ (NSSet *)keyPathsForValuesAffectingVideoDeviceFormat
{
	return [NSSet setWithObjects:@"selectedVideoDevice.activeFormat", nil];
}

- (AVCaptureDeviceFormat *)videoDeviceFormat
{
	return [[self selectedVideoDevice] activeFormat];
}

- (void)setVideoDeviceFormat:(AVCaptureDeviceFormat *)deviceFormat
{
	NSError *error = nil;
	AVCaptureDevice *videoDevice = [self selectedVideoDevice];
	if ([videoDevice lockForConfiguration:&error]) {
		[videoDevice setActiveFormat:deviceFormat];
		[videoDevice unlockForConfiguration];
	} else {
		dispatch_async(dispatch_get_main_queue(), ^(void) {
			[self presentError:error];
		});
	}
}

+ (NSSet *)keyPathsForValuesAffectingAudioDeviceFormat
{
	return [NSSet setWithObjects:@"selectedAudioDevice.activeFormat", nil];
}

- (AVCaptureDeviceFormat *)audioDeviceFormat
{
	return [[self selectedAudioDevice] activeFormat];
}

- (void)setAudioDeviceFormat:(AVCaptureDeviceFormat *)deviceFormat
{
	NSError *error = nil;
	AVCaptureDevice *audioDevice = [self selectedAudioDevice];
	if ([audioDevice lockForConfiguration:&error]) {
		[audioDevice setActiveFormat:deviceFormat];
		[audioDevice unlockForConfiguration];
	} else {
		dispatch_async(dispatch_get_main_queue(), ^(void) {
			[self presentError:error];
		});
	}
}

+ (NSSet *)keyPathsForValuesAffectingFrameRateRange
{
	return [NSSet setWithObjects:@"selectedVideoDevice.activeFormat.videoSupportedFrameRateRanges", @"selectedVideoDevice.activeVideoMinFrameDuration", nil];
}

- (AVFrameRateRange *)frameRateRange
{
	AVFrameRateRange *activeFrameRateRange = nil;
	for (AVFrameRateRange *frameRateRange in [[[self selectedVideoDevice] activeFormat] videoSupportedFrameRateRanges])
	{
		if (CMTIME_COMPARE_INLINE([frameRateRange minFrameDuration], ==, [[self selectedVideoDevice] activeVideoMinFrameDuration]))
		{
			activeFrameRateRange = frameRateRange;
			break;
		}
	}
	
	return activeFrameRateRange;
}

- (void)setFrameRateRange:(AVFrameRateRange *)frameRateRange
{
	NSError *error = nil;
	if ([[[[self selectedVideoDevice] activeFormat] videoSupportedFrameRateRanges] containsObject:frameRateRange])
	{
		if ([[self selectedVideoDevice] lockForConfiguration:&error]) {
			[[self selectedVideoDevice] setActiveVideoMinFrameDuration:[frameRateRange minFrameDuration]];
			[[self selectedVideoDevice] unlockForConfiguration];
		} else {
			dispatch_async(dispatch_get_main_queue(), ^(void) {
				[self presentError:error];
			});
		}
	}
}

- (IBAction)lockVideoDeviceForConfiguration:(id)sender
{
	if ([(NSButton *)sender state] == NSOnState)
	{
		[[self selectedVideoDevice] lockForConfiguration:nil];
	}
	else
	{
		[[self selectedVideoDevice] unlockForConfiguration];
	}
}

#pragma mark - Recording

+ (NSSet *)keyPathsForValuesAffectingHasRecordingDevice
{
	return [NSSet setWithObjects:@"selectedVideoDevice", @"selectedAudioDevice", nil];
}

- (BOOL)hasRecordingDevice
{
	return ((videoDeviceInput != nil) || (audioDeviceInput != nil));
}

+ (NSSet *)keyPathsForValuesAffectingRecording
{
	return [NSSet setWithObject:@"movieFileOutput.recording"];
}

- (BOOL)isRecording
{
	return [[self movieFileOutput] isRecording];
}

- (void)setRecording:(BOOL)record
{
	if (record) {
		time_t rawtime;
		struct tm * timeinfo;
		time ( &rawtime );
		timeinfo = localtime ( &rawtime );
		
		NSString *path = [[NSString stringWithFormat:@"~/Desktop/%04d%02d%02d-%02d%02d%02d.mov",
						   timeinfo->tm_year + 1900, timeinfo->tm_mon + 1, timeinfo->tm_mday, timeinfo->tm_hour, timeinfo->tm_min, timeinfo->tm_sec] stringByExpandingTildeInPath];
		[[self movieFileOutput] startRecordingToOutputFileURL:[NSURL fileURLWithPath:path] recordingDelegate:self];
	} else {
		[[self movieFileOutput] stopRecording];
	}
}

+ (NSSet *)keyPathsForValuesAffectingAvailableSessionPresets
{
	return [NSSet setWithObjects:@"selectedVideoDevice", @"selectedAudioDevice", nil];
}

- (NSArray *)availableSessionPresets
{
	NSArray *allSessionPresets = [NSArray arrayWithObjects:
								  AVCaptureSessionPresetLow,
								  AVCaptureSessionPresetMedium,
								  AVCaptureSessionPresetHigh,
								  AVCaptureSessionPreset320x240,
								  AVCaptureSessionPreset352x288,
								  AVCaptureSessionPreset640x480,
								  AVCaptureSessionPreset960x540,
								  AVCaptureSessionPreset1280x720,
								  AVCaptureSessionPresetPhoto,
								  nil];
	
	NSMutableArray *availableSessionPresets = [NSMutableArray arrayWithCapacity:9];
	for (NSString *sessionPreset in allSessionPresets) {
		if ([[self session] canSetSessionPreset:sessionPreset])
			[availableSessionPresets addObject:sessionPreset];
	}
	
	return availableSessionPresets;
}

#pragma mark - Audio Preview

- (float)previewVolume
{
	return [[self audioPreviewOutput] volume];
}

- (void)setPreviewVolume:(float)newPreviewVolume
{
	[[self audioPreviewOutput] setVolume:newPreviewVolume];
}

- (void)updateAudioLevels:(NSTimer *)timer
{
	double timestamp = CMTimeGetSeconds(movieFileOutput.recordedDuration);
	if (movieFileOutput.isRecording && !isnan(timestamp))
	{
		int minutes = timestamp / 60;
		double seconds = timestamp - minutes * 60;
		_timestampLabel.stringValue = [NSString stringWithFormat:@"%03d:%05.2f", minutes, seconds];
	}

	NSInteger channelCount = 0;
	for (AVCaptureConnection *connection in [[self movieFileOutput] connections]) {
		for (AVCaptureAudioChannel *audioChannel in [connection audioChannels]) {
			float decibels = [audioChannel averagePowerLevel];
			float peak = [audioChannel peakHoldLevel];
			if (channelCount == 0)
			{
				[[self audioLevelMeterL] setFloatValue:(pow(10.f, 0.05f * decibels) * 20.0f)];
				[[self audioLevelL] setStringValue:[NSString stringWithFormat:@"%.1f",decibels]];
				if (peak > [[self audioPeakL] floatValue])
					[[self audioPeakL] setStringValue:[NSString stringWithFormat:@"%.1f",peak]];
				[[self audioWaveformL] appendAmplitude:decibels];
			}
			else if (channelCount == 1)
			{
				[[self audioLevelMeterR] setFloatValue:(pow(10.f, 0.05f * decibels) * 20.0f)];
				[[self audioLevelR] setStringValue:[NSString stringWithFormat:@"%.1f",decibels]];
				if (peak > [[self audioPeakR] floatValue])
					[[self audioPeakR] setStringValue:[NSString stringWithFormat:@"%.1f",peak]];
				[[self audioWaveformR] appendAmplitude:decibels];
			}
			channelCount += 1;
		}
	}
}

#pragma mark - Transport Controls

- (IBAction)stop:(id)sender
{
	[self setTransportMode:AVCaptureDeviceTransportControlsNotPlayingMode speed:0.f forDevice:[self selectedVideoDevice]];
}

+ (NSSet *)keyPathsForValuesAffectingPlaying
{
	return [NSSet setWithObjects:@"selectedVideoDevice.transportControlsPlaybackMode", @"selectedVideoDevice.transportControlsSpeed",nil];
}

- (BOOL)isPlaying
{
	AVCaptureDevice *device = [self selectedVideoDevice];
	return ([device transportControlsSupported] &&
			[device transportControlsPlaybackMode] == AVCaptureDeviceTransportControlsPlayingMode &&
			[device transportControlsSpeed] == 1.f);
}

- (void)setPlaying:(BOOL)play
{
	AVCaptureDevice *device = [self selectedVideoDevice];
	[self setTransportMode:AVCaptureDeviceTransportControlsPlayingMode speed:play ? 1.f : 0.f forDevice:device];
}

+ (NSSet *)keyPathsForValuesAffectingRewinding
{
	return [NSSet setWithObjects:@"selectedVideoDevice.transportControlsPlaybackMode", @"selectedVideoDevice.transportControlsSpeed",nil];
}

- (BOOL)isRewinding
{
	AVCaptureDevice *device = [self selectedVideoDevice];
	return [device transportControlsSupported] && ([device transportControlsSpeed] < -1.f);
}

- (void)setRewinding:(BOOL)rewind
{
	AVCaptureDevice *device = [self selectedVideoDevice];
	[self setTransportMode:[device transportControlsPlaybackMode] speed:rewind ? -2.f : 0.f forDevice:device];
}

+ (NSSet *)keyPathsForValuesAffectingFastForwarding
{
	return [NSSet setWithObjects:@"selectedVideoDevice.transportControlsPlaybackMode", @"selectedVideoDevice.transportControlsSpeed",nil];
}

- (BOOL)isFastForwarding
{
	AVCaptureDevice *device = [self selectedVideoDevice];
	return [device transportControlsSupported] && ([device transportControlsSpeed] > 1.f);
}

- (void)setFastForwarding:(BOOL)fastforward
{
	AVCaptureDevice *device = [self selectedVideoDevice];
	[self setTransportMode:[device transportControlsPlaybackMode] speed:fastforward ? 2.f : 0.f forDevice:device];
}

- (void)setTransportMode:(AVCaptureDeviceTransportControlsPlaybackMode)playbackMode speed:(AVCaptureDeviceTransportControlsSpeed)speed forDevice:(AVCaptureDevice *)device
{
	NSError *error = nil;
	if ([device transportControlsSupported]) {
		if ([device lockForConfiguration:&error]) {
			[device setTransportControlsPlaybackMode:playbackMode speed:speed];
			[device unlockForConfiguration];
		} else {
			dispatch_async(dispatch_get_main_queue(), ^(void) {
				[self presentError:error];
			});
		}
	}
}

#pragma mark - Delegate methods

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
	_recordButton.title = @"Recording…";
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didPauseRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
	NSLog(@"Did pause recording to %@", [fileURL description]);
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didResumeRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
	NSLog(@"Did resume recording to %@", [fileURL description]);
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput willFinishRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections dueToError:(NSError *)error
{
	dispatch_async(dispatch_get_main_queue(), ^(void) {
		[self presentError:error];
	});
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)recordError
{
	_recordButton.title = @"Record";
	_timestampLabel.stringValue = @"";

	if (recordError != nil && [[[recordError userInfo] objectForKey:AVErrorRecordingSuccessfullyFinishedKey] boolValue] == NO) {
		[[NSFileManager defaultManager] removeItemAtURL:outputFileURL error:nil];
		dispatch_async(dispatch_get_main_queue(), ^(void) {
			[self presentError:recordError];
		});
	}
}

- (BOOL)captureOutputShouldProvideSampleAccurateRecordingStart:(AVCaptureOutput *)captureOutput
{
    // We don't require frame accurate start when we start a recording. If we answer YES, the capture output
    // applies outputSettings immediately when the session starts previewing, resulting in higher CPU usage
    // and shorter battery life.
    return NO;
}

@end


@implementation CustomTextField
- (void)mouseDown:(NSEvent *)theEvent
{
	[[self.doc audioPeakL] setFloatValue:-99];
	[[self.doc audioPeakR] setFloatValue:-99];
}
@end
