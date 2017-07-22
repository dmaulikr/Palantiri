//
//  AnorGLView.h
//  AnorStone
//
//  Created by Paul Schifferer on 21/7/17.
//  Copyright © 2017 Pilgrimage Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>
@import CoreVideo;


@interface AnorGLView : NSOpenGLView {
    
@private
    NSRecursiveLock* _lock;

}

@property (nonatomic, assign) CVImageBufferRef imageBuffer;
@property (nonatomic, retain) CIContext* ciContext;
@property (nonatomic, assign) BOOL needsReshape;

@end
