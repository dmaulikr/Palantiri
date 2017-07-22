//
//  AnorViewController.m
//  AnorStone
//
//  Created by Paul Schifferer on 18/7/17.
//  Copyright © 2017 Pilgrimage Software. All rights reserved.
//

#import "AnorViewController.h"
@import CoreGraphics;
@import VideoToolbox;
@import CoreImage;


//static NSInteger PORT_NUMBER = 11924;
static NSInteger BUFFER_SIZE = 1024;


void decodeFrame(void *decompressionOutputRefCon,
                 void *sourceFrameRefCon,
                 OSStatus status,
                 VTDecodeInfoFlags infoFlags,
                 CVImageBufferRef imageBuffer,
                 CMTime presentationTimeStamp,
                 CMTime presentationDuration);

@implementation AnorViewController {
    
@private
    NSNetService* _service;
    NSMutableData* _data;
    NSInputStream* _inputStream;
    NSOutputStream* _outputStream;

    VTDecompressionSessionRef _session;
    CMVideoFormatDescriptionRef _formatDesc;
    int _spsSize;
    int _ppsSize;

}

- (void)viewDidLoad {
    [super viewDidLoad];

    _data = [NSMutableData new];

//        self.videoLayer = [[AVSampleBufferDisplayLayer alloc] init];
//        self.videoLayer.frame = self.view.bounds;
//        self.videoLayer.position = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
//        self.videoLayer.videoGravity = AVLayerVideoGravityResizeAspect;
//        self.videoLayer.backgroundColor = [[NSColor greenColor] CGColor];
//
//        CMTimebaseRef controlTimebase;
//        CMTimebaseCreateWithMasterClock(CFAllocatorGetDefault(), CMClockGetHostTimeClock(), &controlTimebase);
//
//        self.videoLayer.controlTimebase = controlTimebase;
//        CMTimebaseSetTime(self.videoLayer.controlTimebase, CMTimeMake(5, 1));
//        CMTimebaseSetRate(self.videoLayer.controlTimebase, 1.0);
//
//        // connect the video layer with the view
//        [self.view.layer addSublayer:_videoLayer];

    //    self.glView.layer.backgroundColor = [NSColor greenColor].CGColor;

//    [self.glView prepareOpenGL];
//    [self.glView clearGLContext];

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

    /* Create CIContext */
    _glView.ciContext = [CIContext contextWithCGLContext:_glView.openGLContext.CGLContextObj
                                      pixelFormat:_glView.pixelFormat.CGLPixelFormatObj
                                                 options:@{
                                                           kCIContextOutputColorSpace : (__bridge id)colorSpace,
                                                           kCIContextWorkingColorSpace : (__bridge id)colorSpace,
                                                           }];
    _glView.needsReshape = YES;
    CGColorSpaceRelease(colorSpace);

    [self setupListener];
}

- (void)viewDidLayout {
    [super viewDidLayout];

//        self.videoLayer.frame = self.view.bounds;
    _glView.needsReshape = YES;
    [_glView setNeedsDisplay:YES];
}

- (void)setupListener {

    _service = [[NSNetService alloc] initWithDomain:@"local"
                                               type:@"_palantiri._tcp"
                                               name:@"AnorStone"
                                               port:0];
    _service.delegate = self;
    [_service scheduleInRunLoop:[NSRunLoop currentRunLoop]
                        forMode:NSDefaultRunLoopMode];
    [_service publishWithOptions:(NSNetServiceNoAutoRename |
                                  NSNetServiceListenForConnections)];
}

- (void)setupDecodingSession {

    // setup decoding session
    VTDecompressionOutputCallbackRecord callBackRecord;
    callBackRecord.decompressionOutputCallback = decodeFrame;
    callBackRecord.decompressionOutputRefCon = (__bridge void *)self;

    CFDictionaryRef bufferAttrs = CFBridgingRetain(@{
                                                 (id)kCVPixelBufferOpenGLCompatibilityKey : (id)kCFBooleanTrue,
                                                 (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
                                                     });
    OSStatus err = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                                _formatDesc,
                                                NULL,
                                                bufferAttrs,
                                                &callBackRecord,
                                                &_session);
    //    NSLog(@"%@: err=%ld", NSStringFromSelector(_cmd), (long)err);
}

- (int)findStartCodeInData:(NSData*)data startingFromOffset:(int)offset {

    for(;;) {
        if(offset + 4 >= [data length]) {
            return -1;
        }

        uint8_t chunk[4];
        [data getBytes:chunk range:NSMakeRange(offset, 4)];
        if(chunk[0] == 0x00 && chunk[1] == 0x00 && chunk[2] == 0x00 && chunk[3] == 0x01) {
            // found a "start code"
            return offset;
        }

        offset += 1;
    }
}

- (void)processStream {

    //    const uint8_t* frame = [_data bytes];
    //    uint32_t frameSize = [_data length];

    NSData* spsData = nil;
    NSData* ppsData = nil;
    NSMutableData* frameData = nil;

    // loop over data, starting at offset 0
    // check if the 4-byte chunk at the offset is a "start code"
    int offset = [self findStartCodeInData:_data startingFromOffset:0];

    for(;;) {
        // if so, find next "start code" or end of data, calculate length of the chunk
        int nextOffset = [self findStartCodeInData:_data startingFromOffset:offset+1];

        // extract the chunk
        NSRange range = NSMakeRange(offset + 4, nextOffset - offset - 4);
        if(nextOffset == -1) { // end of data
            range.length = [_data length] - offset - 4;
        }
        NSData* chunkData = [_data subdataWithRange:range];

        // look at the first byte of the chunk, which should be the NALU type
        uint8_t naluType;
        [chunkData getBytes:&naluType length:1];
        naluType = (naluType & 0x1F); // not sure what the upper portion is, but we only want the lower 5 bits

        // "process" the chunk according to the type
        switch(naluType) {
            case 7: { // SPS
                spsData = [chunkData subdataWithRange:NSMakeRange(0, [chunkData length])];
                //                sps = [spsData bytes];
            }
                break;

            case 8: { // PPS
                ppsData = [chunkData subdataWithRange:NSMakeRange(0, [chunkData length])];
                //                pps = [ppsData bytes];
            }
                break;

            case 6: { // SEI
                // ???
            }
                break;

            case 5: // IDR frame
            case 1: { // non-IDR picture

                NSData* d = [chunkData subdataWithRange:NSMakeRange(0, [chunkData length])];
                frameData = [NSMutableData new];
                uint32_t dataLength = htonl([d length]);
                [frameData appendBytes:&dataLength length:sizeof(dataLength)];
                [frameData appendData:d];

                [self processFrame:frameData
                           spsData:spsData
                           ppsData:ppsData];
            }
                break;
        }

        // adjust the offset to the next "start code", or exit if we're out of data
        if(nextOffset == -1) break;
        offset = nextOffset;
    }

}

- (void)processFrame:(NSData*)frameData
             spsData:(NSData*)spsData
             ppsData:(NSData*)ppsData {

    uint8_t* frame = [frameData bytes];

    if(_formatDesc == nil) {
        uint8_t* sps = [spsData bytes];
        uint8_t* pps = [ppsData bytes];

        // now we set our H264 parameters
        uint8_t* parameterSetPointers[2] = { sps, pps };
        size_t parameterSetSizes[2] = { [spsData length], [ppsData length] };

        OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                              2,
                                                                              (const uint8_t* const *)parameterSetPointers,
                                                                              parameterSetSizes,
                                                                              4,
                                                                              &_formatDesc);

        //    NSLog(@"Creation of CMVideoFormatDescription: %@", (status == noErr) ? @"successful!" : @"failed...");
        if(status != noErr) {
            NSLog(@"Format Description ERROR type: %d", (int)status);
        }
    }

    long blockLength = [frameData length];

    CMBlockBufferRef blockBuffer = NULL;

    if(_session == NULL) {
        [self setupDecodingSession];
    }

    // create a block buffer from the IDR NALU
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                                                         frame,
                                                         blockLength,
                                                         kCFAllocatorDefault,
                                                         NULL,
                                                         0,
                                                         blockLength,
                                                         0,
                                                         &blockBuffer);

    CMSampleBufferRef sampleBuffer = NULL;
    const size_t sampleSize = blockLength;
    status = CMSampleBufferCreate(kCFAllocatorDefault,
                                  blockBuffer,
                                  true,
                                  NULL,
                                  NULL,
                                  _formatDesc,
                                  1,
                                  0,
                                  NULL,
                                  1,
                                  &sampleSize,
                                  &sampleBuffer);

    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
    CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
    CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);

    [self renderFrame:sampleBuffer];
    CFRelease(sampleBuffer);
}

- (void)renderFrame:(CMSampleBufferRef)buffer {

    VTDecodeFrameFlags frameFlags = kVTDecodeFrame_EnableAsynchronousDecompression;
    VTDecodeInfoFlags decodeFlags = 0;
    NSDate* now = [NSDate date];
    OSStatus err = VTDecompressionSessionDecodeFrame(_session,
                                                     buffer,
                                                     frameFlags,
                                                     (void*)CFBridgingRetain(now),
                                                     &decodeFlags);
//        NSLog(@"err=%ld", (long)err);

//    // put it on the screen
//    if ([_videoLayer isReadyForMoreMediaData]) {
//        [_videoLayer enqueueSampleBuffer:buffer];
//    }
}

- (void)netServiceDidStop:(NSNetService *)sender {
    //    NSLog(@"%@: %@", NSStringFromSelector(_cmd), sender);

}

- (void)netServiceDidPublish:(NSNetService *)sender {
    NSLog(@"%@: %@", NSStringFromSelector(_cmd), sender);

}

- (void)netServiceWillPublish:(NSNetService *)sender {
    //    NSLog(@"%@: %@", NSStringFromSelector(_cmd), sender);

}

- (void)netServiceWillResolve:(NSNetService *)sender {
    //    NSLog(@"%@: %@", NSStringFromSelector(_cmd), sender);

}

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    //    NSLog(@"%@: %@, error: %@", NSStringFromSelector(_cmd), sender, errorDict);

}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    NSLog(@"%@: %@, error: %@", NSStringFromSelector(_cmd), sender, errorDict);

}

- (void)netServiceDidResolveAddress:(NSNetService *)sender {
    //    NSLog(@"%@: %@", NSStringFromSelector(_cmd), sender);

}

- (void)netService:(NSNetService *)sender didAcceptConnectionWithInputStream:(NSInputStream *)inputStream outputStream:(NSOutputStream *)outputStream {
    NSLog(@"%@: %@", NSStringFromSelector(_cmd), sender);

    [self setupDecodingSession];

    _inputStream = inputStream;
    _inputStream.delegate = self;
    _outputStream = outputStream;
    _outputStream.delegate = self;

    [_inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop]
                            forMode:NSDefaultRunLoopMode];
    [_outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop]
                             forMode:NSDefaultRunLoopMode];

    [_inputStream open];
    [_outputStream open];
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode {
    //    NSLog(@"%@: %@, %ld", NSStringFromSelector(_cmd), stream, eventCode);

    uint8_t buffer[BUFFER_SIZE];

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
            //            NSLog(@"NSStreamEventHasBytesAvailable: %ld", [stream streamStatus]);

            while([(NSInputStream*)stream hasBytesAvailable]) {
                NSUInteger length = [(NSInputStream*)stream read:buffer maxLength:BUFFER_SIZE];
                //                NSLog(@"length=%ld", length);

                switch(length) {
                    case -1:
                        NSLog(@"Read from stream encountered an error: %@", [stream streamError]);
                        return;

                    case 0: // end of buffer
                        //                        [_data appendBytes:buffer length:BUFFER_SIZE];
                        break;

                    default:
                        [_data appendBytes:buffer length:length];
                        break;
                }

                // "assume" that if last read was shorter than the full buffer, that it's the end of the data
                if(length < BUFFER_SIZE) {
                    
                    [self processStream];

                    // reset the data buffer
                    _data = [NSMutableData new];
                    _formatDesc = NULL;
                }
            }
            break;

        case NSStreamEventHasSpaceAvailable:
            //            NSLog(@"NSStreamEventHasSpaceAvailable: ");
            break;

        case NSStreamEventOpenCompleted:
            //            NSLog(@"NSStreamEventOpenCompleted: %ld", [stream streamStatus]);
            break;
    }
}

@end

void decodeFrame(void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef imageBuffer, CMTime presentationTimeStamp, CMTime presentationDuration) {

    if(infoFlags & kVTDecodeInfo_FrameDropped) return;

    AnorViewController* vc = (__bridge AnorViewController*)decompressionOutputRefCon;

//    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:imageBuffer];

    vc.glView.currentFrame = imageBuffer;
       dispatch_async(dispatch_get_main_queue(), ^{
    [vc.glView setNeedsDisplay:YES];
       });

////    CIContext *ciContext = [CIContext contextWithOptions:nil];
////    CGFloat width = CVPixelBufferGetWidth(imageBuffer);
////    CGFloat height = CVPixelBufferGetHeight(imageBuffer);
////    CGImageRef cgImage = [ciContext
////                          createCGImage:ciImage
////                          fromRect:CGRectMake(0, 0, width, height)];
////
////    NSImage *image = [[NSImage alloc] initWithCGImage:cgImage
////                                                 size:NSMakeSize(width, height)];
//
//    dispatch_async(dispatch_get_main_queue(), ^{
////        vc.imageView.image = image;
////
////        CGImageRelease(cgImage);
////        NSData* imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:sampleBuffer];
////        NSImage* frameImage = [NSImage imageWithData:imageData];
//                CGLContextObj glContext = vc.glView.openGLContext.CGLContextObj;
//                CIContext *ciContext = [CIContext contextWithCGLContext:glContext
//                                                            pixelFormat:vc.glView.openGLContext.pixelFormat.CGLPixelFormatObj
//                                                             colorSpace:CGColorSpaceCreateDeviceRGB()
//                                                                options:nil];
//                [ciContext drawImage:ciImage
//                              inRect:vc.glView.frame
//                            fromRect:ciImage.extent];
//        [vc.glView update];
////        [vc.glView setNeedsDisplay:YES];
//    });
//
//    //    CGImageRelease(ciImage);
}

