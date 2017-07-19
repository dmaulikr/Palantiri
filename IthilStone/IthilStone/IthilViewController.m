//
//  IthilViewController.m
//  IthilStone
//
//  Created by Paul Schifferer on 18/7/17.
//  Copyright © 2017 Pilgrimage Software. All rights reserved.
//

#import "IthilViewController.h"
@import CoreGraphics;
@import VideoToolbox;


static NSInteger PORT_NUMBER = 11924;

@implementation IthilViewController {

@private
    CGDirectDisplayID _displayId;
    CGSize _displaySize;
    CGDisplayStreamRef _stream;
    VTCompressionSessionRef _session;
    NSOutputStream* _outputStream;

}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleWindowMove:)
                                                 name:NSWindowDidMoveNotification
                                               object:nil];

    // get initial window info
    [self getDisplay];
    [self updateWindowInfo];

    [self setupEncodingSession];
    [self setupDisplayStream];
}

- (void)setupEncodingSession {

    // setup encoding session
    CFDictionaryRef sourceBufferAttrs = CFBridgingRetain(@{
                                                           (id)kVTCompressionPropertyKey_RealTime : @YES,
                                                           });
    OSStatus err = VTCompressionSessionCreate(kCFAllocatorDefault,
                                              _displaySize.width, _displaySize.height,
                                              kCMVideoCodecType_H264,
                                              NULL,
                                              sourceBufferAttrs,
                                              NULL,
                                              NULL,
                                              NULL,
                                              &_session);
    NSLog(@"%@: err=%ld", NSStringFromSelector(_cmd), (long)err);
}

- (void)setupDisplayStream {

    // setup display stream
    CFDictionaryRef streamProperties = CFBridgingRetain(@{
                                                          (id)kCGDisplayStreamShowCursor : @NO,
                                                          });
    _stream = CGDisplayStreamCreate(_displayId,
                                    _displaySize.width, _displaySize.height,
                                    'BGRA',
                                    streamProperties,
                                    ^(CGDisplayStreamFrameStatus status, uint64_t displayTime, IOSurfaceRef frameSurface, CGDisplayStreamUpdateRef updateRef) {
                                        VTEncodeInfoFlags flags = 0;
                                        CFDictionaryRef frameProperties = CFBridgingRetain(@{

                                                                                             });
                                        CVPixelBufferRef buffer;
                                        CVReturn rc = CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault,
                                                                                       frameSurface,
                                                                                       NULL,
                                                                                       &buffer);
                                        NSLog(@"%@: rc=%ld", NSStringFromSelector(_cmd), (long)rc);
                                        CMTime time = CMTimeMake(displayTime, 1);
                                        OSStatus err = VTCompressionSessionEncodeFrameWithOutputHandler(_session,
                                                                                                        buffer,
                                                                                                        time,
                                                                                                        kCMTimeInvalid,
                                                                                                        frameProperties,
                                                                                                        &flags,
                                                                                                        ^(OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef  _Nullable sampleBuffer) {
                                                                                                            NSLog(@"%@: sampleBuffer=%@", NSStringFromSelector(_cmd), sampleBuffer);
                                                                                                            if(sampleBuffer == NULL) {
                                                                                                                NSLog(@"No sample buffer: status=%ld", (long)status);
                                                                                                                return;
                                                                                                            }

                                                                                                            // send the buffer
                                                                                                            [self sendBuffer:sampleBuffer];
                                                                                                        });
                                        NSLog(@"%@: err=%ld", NSStringFromSelector(_cmd), (long)err);
                                        // TODO
                                    });
    CFRunLoopSourceRef source = CGDisplayStreamGetRunLoopSource(_stream);
    CFRunLoopRef runLoop = CFRunLoopGetCurrent();
    CFRunLoopAddSource(runLoop, source, kCFRunLoopCommonModes);

    CGDisplayStreamStart(_stream);
}

- (void)sendBuffer:(CMSampleBufferRef)buffer {
    NSLog(@"%@: buffer=%@", NSStringFromSelector(_cmd), buffer);

    if(_outputStream == nil) {
        CFHostRef host = CFHostCreateWithName(kCFAllocatorDefault, (CFStringRef)@"localhost");
        CFWriteStreamRef writeStream;
        CFStreamCreatePairWithSocketToCFHost(kCFAllocatorDefault, host, (UInt32)PORT_NUMBER, NULL, &writeStream);
        _outputStream = (NSOutputStream*)CFBridgingRelease(writeStream);
    }

    //    NSUInteger size = (NSUInteger)CMSampleBufferGetSampleSize(buffer, 0);
    CMBlockBufferRef b = CMSampleBufferGetDataBuffer(buffer);
    size_t totalLength = 0;
    char* dataPointer;
    CMBlockBufferGetDataPointer(b, 0, NULL, &totalLength, &dataPointer);
    [_outputStream write:(const uint8_t*)dataPointer maxLength:totalLength];
}

- (void)handleWindowMove:(NSNotification*)note {
    [self getDisplay];
    [self updateWindowInfo];
}

- (void)getDisplay {

    NSWindow* window = [[self view] window];
    NSRect windowRect = [window frame];
    NSPoint screenPoint = [window convertRectToScreen:windowRect].origin;

    CGDirectDisplayID displays[1];
    uint32_t displayCount = 0;
    CGError error = CGGetDisplaysWithPoint(screenPoint, 1, displays, &displayCount);

    if(error > 0 || displayCount < 1) {
        [_displayInfoLabel setStringValue:@"Unable to get display info"];
        return;
    }

    _displayId = displays[0];
}

- (void)updateWindowInfo {

    //    BOOL isCaptured = CGDisplayIsCaptured(_displayId);
    BOOL isMain = CGDisplayIsMain(_displayId);
    _displaySize = CGDisplayScreenSize(_displayId);
    uint32_t unitNum = CGDisplayUnitNumber(_displayId);

    NSString* info = [NSString stringWithFormat:@"%ld:%ld%@, %@",
                      (long)_displayId,
                      (long)unitNum,
                      isMain ? @" (main)" : @"",
                      //                      isCaptured ? @" [captured]" : @"",
                      NSStringFromSize(_displaySize)];
    [_displayInfoLabel setStringValue:info];
}

@end
