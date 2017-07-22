//
//  AnorGLView.m
//  AnorStone
//
//  Created by Paul Schifferer on 21/7/17.
//  Copyright © 2017 Pilgrimage Software. All rights reserved.
//

#import "AnorGLView.h"
#import <OpenGL/gl.h>
@import CoreImage;


@implementation AnorGLView

- (void)awakeFromNib {
    [super awakeFromNib];

    _lock = [NSLock new];
}

- (void)drawRect:(NSRect)dirtyRect {
    
    [_lock lock];
    
    NSRect frame = [self frame];
    NSRect bounds = [self bounds];
    
    [[self openGLContext] makeCurrentContext];
    
    if(_needsReshape) {
        GLfloat minX, minY, maxX, maxY;
        
        minX = NSMinX(bounds);
        minY = NSMinY(bounds);
        maxX = NSMaxX(bounds);
        maxY = NSMaxY(bounds);
        
        [self update];
        
        if(NSIsEmptyRect([self visibleRect])) {
            glViewport(0, 0, 1, 1);
        }
        else {
            glViewport(0, 0, frame.size.width ,frame.size.height);
        }
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        glOrtho(minX, maxX, minY, maxY, -1.0, 1.0);
        
        _needsReshape = NO;
    }
    
    glClearColor(0.0, 1.0, 0.5, 0.0);
    glClear(GL_COLOR_BUFFER_BIT);
    
    //    if(!_currentFrame) {
    //        [self updateCurrentFrame];
    //    }
    
    [self renderCurrentFrame];
    
    glFlush();
    
    [_lock unlock];
    
}

- (void)renderCurrentFrame {
    
    NSRect frame = [self frame];
    
    if(_currentFrame) {
        CIImage* inputImage = [CIImage imageWithCVImageBuffer:_currentFrame];
        CGRect imageRect = [inputImage extent];
        [_ciContext drawImage:inputImage
                      atPoint:CGPointMake((int)((frame.size.width - imageRect.size.width) * 0.5),
                                          (int)((frame.size.height - imageRect.size.height) * 0.5))
                     fromRect:imageRect];
    }
}

- (void)setCurrentFrame:(CVImageBufferRef)currentFrame {
    [_lock lock];
    if(_currentFrame) {
        CFRelease(_currentFrame);
        _currentFrame = nil;
    }
    
    if(currentFrame) {
        _currentFrame = CFRetain(currentFrame);
    }
    [_lock unlock];
}

@end
