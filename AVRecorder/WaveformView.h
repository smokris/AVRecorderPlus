//
//  WaveformView.h
//  AVRecorder
//
//  Created by Steve Mokris on 9/6/15.
//
//

#import <Cocoa/Cocoa.h>

@interface WaveformView : NSView
{
	float amplitudes[200];
}
- (void)appendAmplitude:(float)amplitude;
@end
