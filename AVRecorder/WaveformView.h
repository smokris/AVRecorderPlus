#import <Cocoa/Cocoa.h>

@interface WaveformView : NSView
{
	float amplitudes[200];
}
- (void)appendAmplitude:(float)amplitude;
@end
