//
//  AnorViewController.h
//  AnorStone
//
//  Created by Paul Schifferer on 18/7/17.
//  Copyright © 2017 Pilgrimage Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>
@import AVFoundation;
#import "AnorGLView.h"


@interface AnorViewController : NSViewController <NSStreamDelegate, NSNetServiceDelegate>

//@property (nonatomic, weak) IBOutlet NSView* containerView;
@property (nonatomic, weak) IBOutlet AnorGLView* glView;
//@property (nonatomic, weak) IBOutlet NSImageView* imageView;

//@property (nonatomic, retain) AVSampleBufferDisplayLayer *videoLayer;

@end

