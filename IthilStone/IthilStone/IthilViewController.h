//
//  IthilViewController.h
//  IthilStone
//
//  Created by Paul Schifferer on 18/7/17.
//  Copyright © 2017 Pilgrimage Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface IthilViewController : NSViewController <NSStreamDelegate>

@property (weak) IBOutlet NSTextField *displayInfoLabel;

@end

