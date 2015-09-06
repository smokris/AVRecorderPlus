//
//  WaveformView.m
//  AVRecorder
//
//  Created by Steve Mokris on 9/6/15.
//
//

#import "WaveformView.h"

@implementation WaveformView

- (void)appendAmplitude:(float)amplitude
{
	memmove(amplitudes, amplitudes+1, sizeof(float)*199);
	amplitudes[199] = amplitude;
	
    [self setNeedsDisplay:YES];
}

- (void)line:(float)y color:(NSColor *)color
{
	float minX = NSMinX([self bounds]);
	float maxX = NSMaxX([self bounds]);
	float topY = NSMaxY([self bounds]);

	NSBezierPath *line = [NSBezierPath bezierPath];
	[line moveToPoint:NSMakePoint(minX, topY - y - 0.5)];
	[line lineToPoint:NSMakePoint(maxX, topY - y - 0.5)];
	[line setLineWidth:1.0];
	[color set];
	[line stroke];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

	[[NSColor blackColor] set];
	NSRectFillUsingOperation([self bounds], NSCompositeCopy);

	[self line:30 color:[NSColor grayColor]];
	[self line:30-12 color:[NSColor yellowColor]];
	[self line:30-13 color:[NSColor redColor]];
	
	float minX = NSMinX([self bounds]);
	float maxX = NSMaxX([self bounds]);
	float topY = NSMaxY([self bounds]);

	NSBezierPath *line = [NSBezierPath bezierPath];
	for (int i = 0; i < 200; ++i)
	{
		NSPoint p = NSMakePoint((maxX-minX)*(float)i/200 + minX, topY - 30 + amplitudes[i]);
		if (i == 0)
			[line moveToPoint:p];
		else
			[line lineToPoint:p];
	}
	[line setLineWidth:2.0];
	[[NSColor whiteColor] set];
	[line stroke];
}

@end
