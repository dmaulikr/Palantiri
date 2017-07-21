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


void handleSample(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer);

@implementation IthilViewController {

@private
    CGSize _displaySize;
    CGDisplayStreamRef _stream;
    VTCompressionSessionRef _session;
    NSInputStream* _inputStream;
    NSOutputStream* _outputStream;
    NSNetServiceBrowser* _browser;
    NSNetService* _service;

}

- (void)viewDidLoad {
    [super viewDidLoad];

    _displaySize = CGDisplayScreenSize(CGMainDisplayID());

    [self setupServiceBrowser];
}

- (void)setupServiceBrowser {

    _browser = [[NSNetServiceBrowser alloc] init];
    _browser.delegate = self;
    _browser.includesPeerToPeer = YES;

    [_browser scheduleInRunLoop:[NSRunLoop currentRunLoop]
                        forMode:NSDefaultRunLoopMode];
    [_browser searchForServicesOfType:@"_palantiri._tcp"
                             inDomain:@"local"];

    [self.view.window orderOut:self];
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
    _stream = CGDisplayStreamCreate(CGMainDisplayID(),
                                    _displaySize.width, _displaySize.height,
                                    'BGRA',
                                    streamProperties,
                                    ^(CGDisplayStreamFrameStatus status, uint64_t displayTime, IOSurfaceRef frameSurface, CGDisplayStreamUpdateRef updateRef) {
                                        //                                        NSLog(@"CGDisplayStreamCreate[callback]: status=%ld, displayTime=%ld, frameSurface=%@, updateRef=%@", (long)status, (long)displayTime, frameSurface, updateRef);
                                        VTEncodeInfoFlags flags = 0;
                                        CFDictionaryRef frameProperties = CFBridgingRetain(@{
                                                                                             (id)kVTCompressionPropertyKey_RealTime : @YES,
                                                                                             });
                                        CVPixelBufferRef pixelBuffer;
                                        CVReturn rc = CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault,
                                                                                       frameSurface,
                                                                                       NULL,
                                                                                       &pixelBuffer);
                                        //                                        NSLog(@"CGDisplayStreamCreate[callback]: rc=%ld, pixelBuffer=%p", (long)rc, pixelBuffer);
                                        CMTime time = CMTimeMake(displayTime, 1);
                                        OSStatus err = VTCompressionSessionEncodeFrame(_session,
                                                                                       pixelBuffer,
                                                                                       time,
                                                                                       kCMTimeInvalid,
                                                                                       frameProperties,
                                                                                       (__bridge void*)self,
                                                                                       &flags);
                                        //                                        VTCompressionSessionEndPass(_session, NULL, NULL);
                                        CVPixelBufferRelease(pixelBuffer);
                                        CFRelease(frameProperties);
                                        //                                        NSLog(@"CGDisplayStreamCreate[callback]: err=%ld", (long)err);
                                    });
    CFRelease(streamProperties);
    CFRunLoopSourceRef source = CGDisplayStreamGetRunLoopSource(_stream);
    CFRunLoopRef runLoop = CFRunLoopGetCurrent();
    CFRunLoopAddSource(runLoop, source, kCFRunLoopCommonModes);

    CGDisplayStreamStart(_stream);
}

- (void)sendBuffer:(CMSampleBufferRef)buffer {
    //    NSLog(@"%@: buffer=%p", NSStringFromSelector(_cmd), buffer);

    if(_outputStream == nil) {
        return;
    }

    NSMutableData* elementaryStream = [NSMutableData new];

    static const size_t startCodeLength = 4;
    static const uint8_t startCode[] = { 0x00, 0x00, 0x00, 0x01 };

    CMFormatDescriptionRef description = CMSampleBufferGetFormatDescription(buffer);

    // Find out how many parameter sets there are
    size_t numberOfParameterSets;
    CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description,
                                                       0,
                                                       NULL,
                                                       NULL,
                                                       &numberOfParameterSets,
                                                       NULL);

    // Write each parameter set to the elementary stream
    for (int i = 0; i < numberOfParameterSets; i++) {
        const uint8_t *parameterSetPointer;
        size_t parameterSetLength;
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description,
                                                           i,
                                                           &parameterSetPointer,
                                                           &parameterSetLength,
                                                           NULL, NULL);

        // Write the parameter set to the elementary stream
        [elementaryStream appendBytes:startCode length:startCodeLength];
        [elementaryStream appendBytes:parameterSetPointer length:parameterSetLength];
    }

    size_t blockBufferLength;
    uint8_t* bufferDataPointer = NULL;
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(buffer);
    CMBlockBufferGetDataPointer(dataBuffer,
                                0,
                                NULL,
                                &blockBufferLength,
                                (char**)&bufferDataPointer);

    // Loop through all the NAL units in the block buffer
    // and write them to the elementary stream with
    // start codes instead of AVCC length headers
    size_t bufferOffset = 0;
    static const int AVCCHeaderLength = 4;
    while(bufferOffset < blockBufferLength - AVCCHeaderLength) {
        // Read the NAL unit length
        uint32_t NALUnitLength = 0;
        memcpy(&NALUnitLength, bufferDataPointer + bufferOffset, AVCCHeaderLength);
        // Convert the length value from Big-endian to Little-endian
        NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
        // Write start code to the elementary stream
        [elementaryStream appendBytes:startCode
                               length:startCodeLength];
        // Write the NAL unit without the AVCC length header to the elementary stream
        [elementaryStream appendBytes:bufferDataPointer + bufferOffset + AVCCHeaderLength
                               length:NALUnitLength];
        // Move to the next NAL unit in the block buffer
        bufferOffset += AVCCHeaderLength + NALUnitLength;
    }

    NSUInteger length = [_outputStream write:(const uint8_t*)[elementaryStream bytes] maxLength:[elementaryStream length]];
    //    NSLog(@"length=%ld", (long)length);

    switch(length) {
        case -1:
            NSLog(@"Error while writing stream: %@", [_outputStream streamError]);
            break;

        case 0:
            //            NSLog(@"Nothing sent.");
            break;

        default:
            //            NSLog(@"%ld bytes sent.", length);
            break;
    }
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode {
    //    NSLog(@"%@: %@, %ld", NSStringFromSelector(_cmd), stream, eventCode);

    switch(eventCode) {
        case NSStreamEventNone:
            //            NSLog(@"NSStreamEventNone: ");
            break;

        case NSStreamEventEndEncountered:
            //            NSLog(@"NSStreamEventEndEncountered: ");
            break;

        case NSStreamEventErrorOccurred:
            NSLog(@"NSStreamEventErrorOccurred: %@", [stream streamError]);
            break;

        case NSStreamEventHasBytesAvailable:
            //            NSLog(@"NSStreamEventHasBytesAvailable: ");
            break;

        case NSStreamEventHasSpaceAvailable:
            //            NSLog(@"NSStreamEventHasSpaceAvailable: ");
            break;

        case NSStreamEventOpenCompleted:
            //            NSLog(@"NSStreamEventOpenCompleted: ");
            break;
    }
}

- (void)netServiceBrowserWillSearch:(NSNetServiceBrowser *)browser {
    //    NSLog(@"%@: %@", NSStringFromSelector(_cmd), browser);

}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didNotSearch:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    //    NSLog(@"%@: %@, error: %@", NSStringFromSelector(_cmd), browser, errorDict);

}

- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)browser {
    //    NSLog(@"%@: %@", NSStringFromSelector(_cmd), browser);

}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didFindDomain:(NSString *)domainString moreComing:(BOOL)moreComing {
    //    NSLog(@"%@: %@", NSStringFromSelector(_cmd), browser);

}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didFindService:(NSNetService *)service moreComing:(BOOL)moreComing {
        NSLog(@"%@: %@", NSStringFromSelector(_cmd), browser);

    _service = service;

    [service getInputStream:&_inputStream outputStream:&_outputStream];

    _inputStream.delegate = self;
    _outputStream.delegate = self;

    [_inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop]
                            forMode:NSDefaultRunLoopMode];
    [_outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop]
                             forMode:NSDefaultRunLoopMode];

    [_inputStream open];
    [_outputStream open];

    [self setupEncodingSession];
    [self setupDisplayStream];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didRemoveDomain:(NSString *)domainString moreComing:(BOOL)moreComing {
    //    NSLog(@"%@: %@", NSStringFromSelector(_cmd), browser);

}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didRemoveService:(NSNetService *)service moreComing:(BOOL)moreComing {
    //    NSLog(@"%@: %@", NSStringFromSelector(_cmd), browser);

    if(service == _service) {
        _service = nil;
    }
}

@end


void handleSample(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer) {
    //    NSLog(@"handleSample: outputCallbackRefCon=%@, sourceFrameRefCon=%@, status=%ld, infoFlags=%ld, sampleBuffer=%p", outputCallbackRefCon, sourceFrameRefCon, (long)status, (long)infoFlags, sampleBuffer);
    if(sampleBuffer == NULL) {
        NSLog(@"No sample buffer: status=%ld", (long)status);
        return;
    }

    // send the buffer
    IthilViewController* vc = (__bridge IthilViewController*)outputCallbackRefCon;
    [vc sendBuffer:sampleBuffer];
}

