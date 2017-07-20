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

void handleSample(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer);

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
                                              kCFAllocatorDefault,
                                              handleSample,
                                              (__bridge void*)self,
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
                                        NSLog(@"CGDisplayStreamCreate[callback]: status=%ld, displayTime=%ld, frameSurface=%@, updateRef=%@", (long)status, (long)displayTime, frameSurface, updateRef);
                                        VTEncodeInfoFlags flags = 0;
                                        CFDictionaryRef frameProperties = CFBridgingRetain(@{

                                                                                             });
                                        CVPixelBufferRef buffer;
                                        CVReturn rc = CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault,
                                                                                       frameSurface,
                                                                                       NULL,
                                                                                       &buffer);
                                        NSLog(@"CGDisplayStreamCreate[callback]: rc=%ld, buffer=%p", (long)rc, buffer);
                                        CMTime time = CMTimeMake(displayTime, 1);
                                        OSStatus err = VTCompressionSessionEncodeFrame(_session,
                                                                                       buffer,
                                                                                       time,
                                                                                       kCMTimeInvalid,
                                                                                       frameProperties,
                                                                                       (__bridge void*)self,
                                                                                       &flags);
                                        CVPixelBufferRelease(buffer);
                                        CFRelease(frameProperties);
                                        //                                        OSStatus err = VTCompressionSessionEncodeFrameWithOutputHandler(_session,
                                        //                                                                                                        buffer,
                                        //                                                                                                        time,
                                        //                                                                                                        kCMTimeInvalid,
                                        //                                                                                                        frameProperties,
                                        //                                                                                                        &flags,
                                        //                                                                                                        ^(OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef  _Nullable sampleBuffer) {
                                        //                                                                                                            NSLog(@"%@: sampleBuffer=%@", NSStringFromSelector(_cmd), sampleBuffer);
                                        //                                                                                                            if(sampleBuffer == NULL) {
                                        //                                                                                                                NSLog(@"No sample buffer: status=%ld", (long)status);
                                        //                                                                                                                return;
                                        //                                                                                                            }
                                        //
                                        //                                                                                                            // send the buffer
                                        //                                                                                                            [self sendBuffer:sampleBuffer];
                                        //                                                                                                        });
                                        NSLog(@"CGDisplayStreamCreate[callback]: err=%ld", (long)err);
                                        // TODO
                                    });
    CFRelease(streamProperties);
    CFRunLoopSourceRef source = CGDisplayStreamGetRunLoopSource(_stream);
    CFRunLoopRef runLoop = CFRunLoopGetCurrent();
    CFRunLoopAddSource(runLoop, source, kCFRunLoopCommonModes);

    CGDisplayStreamStart(_stream);
}

- (void)sendBuffer:(CMSampleBufferRef)buffer {
    NSLog(@"%@: buffer=%p", NSStringFromSelector(_cmd), buffer);

    if(_outputStream == nil) {
        NSLog(@"Opening new output stream.");
//        CFHostRef host = CFHostCreateWithName(kCFAllocatorDefault, (CFStringRef)@"localhost");
        CFWriteStreamRef writeStream;
        CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, @"127.0.0.1", (UInt32)PORT_NUMBER, NULL, &writeStream);
        _outputStream = (NSOutputStream*)CFBridgingRelease(writeStream);
        _outputStream.delegate = self;
        [_outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop]
                                 forMode:NSRunLoopCommonModes];
        [_outputStream open];
    }

    //    NSUInteger size = (NSUInteger)CMSampleBufferGetSampleSize(buffer, 0);
    CMBlockBufferRef b = CMSampleBufferGetDataBuffer(buffer);
    size_t totalLength = 0;
    char* dataPointer;
    CMBlockBufferGetDataPointer(b, 0, NULL, &totalLength, &dataPointer);
    NSUInteger length = [_outputStream write:(const uint8_t*)dataPointer maxLength:totalLength];
    NSLog(@"length=%ld", (long)length);

    switch(length) {
        case -1:
            NSLog(@"Error while writing stream: %@", [_outputStream streamError]);
            break;

        case 0:
            NSLog(@"Nothing sent.");
            break;

        default:
            NSLog(@"%ld bytes sent.", length);
            break;
    }
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

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode {
    NSLog(@"%@: %@, %ld", NSStringFromSelector(_cmd), stream, eventCode);

    switch(eventCode) {
        case NSStreamEventNone:
            NSLog(@"NSStreamEventNone: ");
            break;

        case NSStreamEventEndEncountered:
            NSLog(@"NSStreamEventEndEncountered: ");
            break;

        case NSStreamEventErrorOccurred:
            NSLog(@"NSStreamEventErrorOccurred: ");
            break;

        case NSStreamEventHasBytesAvailable:
            NSLog(@"NSStreamEventHasBytesAvailable: ");
            break;

        case NSStreamEventHasSpaceAvailable:
            NSLog(@"NSStreamEventHasSpaceAvailable: ");
            break;

        case NSStreamEventOpenCompleted:
            NSLog(@"NSStreamEventOpenCompleted: ");
            break;
    }
}

@end


void handleSample(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer) {
    NSLog(@"handleSample: outputCallbackRefCon=%@, sourceFrameRefCon=%@, status=%ld, infoFlags=%ld, sampleBuffer=%p", outputCallbackRefCon, sourceFrameRefCon, (long)status, (long)infoFlags, sampleBuffer);
    if(sampleBuffer == NULL) {
        NSLog(@"No sample buffer: status=%ld", (long)status);
        return;
    }

    // send the buffer
    IthilViewController* vc = (__bridge IthilViewController*)outputCallbackRefCon;
    [vc sendBuffer:sampleBuffer];
}

