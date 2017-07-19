//
//  AnorViewController.h
//  AnorStone
//
//  Created by Paul Schifferer on 18/7/17.
//  Copyright © 2017 Pilgrimage Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AnorViewController : NSViewController <NSStreamDelegate>

@property (nonatomic, retain) NSInputStream* inputStream;

@end

