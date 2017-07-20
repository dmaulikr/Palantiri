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


static NSInteger PORT_NUMBER = 11924;
static NSInteger BUFFER_SIZE = 1024;


void outputHandler(VTDecompressionSessionRef session, CMSampleBufferRef sampleBuffer, VTDecodeFrameFlags decodeFlags, VTDecodeInfoFlags *infoFlagsOut, VTDecompressionOutputHandler outputHandler);

@implementation AnorViewController {
    
@private
    NSNetService* _service;
    NSMutableData* _data;
    NSInputStream* _inputStream;
    NSOutputStream* _outputStream;
    VTDecompressionSessionRef _session;

}

- (void)viewDidLoad {
    [super viewDidLoad];

    _data = [NSMutableData new];

    [self setupListener];
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

    _playerView.
    // setup decoding session
    CFDictionaryRef bufferAttrs = CFBridgingRetain(@{

                                                           });
    OSStatus err = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                              formatDesc,
                                                decoderSpec,
                                                bufferAttrs,
                                                outputHandler,
                                              &_session);
    NSLog(@"%@: err=%ld", NSStringFromSelector(_cmd), (long)err);
}


- (void)netServiceDidStop:(NSNetService *)sender {
    NSLog(@"%@: %@", NSStringFromSelector(_cmd), sender);

}

- (void)netServiceDidPublish:(NSNetService *)sender {
    NSLog(@"%@: %@", NSStringFromSelector(_cmd), sender);

}

- (void)netServiceWillPublish:(NSNetService *)sender {
    NSLog(@"%@: %@", NSStringFromSelector(_cmd), sender);

}

- (void)netServiceWillResolve:(NSNetService *)sender {
    NSLog(@"%@: %@", NSStringFromSelector(_cmd), sender);

}

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    NSLog(@"%@: %@, error: %@", NSStringFromSelector(_cmd), sender, errorDict);

}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    NSLog(@"%@: %@, error: %@", NSStringFromSelector(_cmd), sender, errorDict);

}

- (void)netServiceDidResolveAddress:(NSNetService *)sender {
    NSLog(@"%@: %@", NSStringFromSelector(_cmd), sender);

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
    NSLog(@"%@: %@, %ld", NSStringFromSelector(_cmd), stream, eventCode);

    uint8_t buffer[BUFFER_SIZE];

    switch(eventCode) {
        case NSStreamEventNone:
            NSLog(@"NSStreamEventNone: ");
            break;

        case NSStreamEventEndEncountered:
            NSLog(@"NSStreamEventEndEncountered: ");
            break;

        case NSStreamEventErrorOccurred:
            NSLog(@"NSStreamEventErrorOccurred: %@", [stream streamError]);
            break;

        case NSStreamEventHasBytesAvailable:
            NSLog(@"NSStreamEventHasBytesAvailable: %ld", [stream streamStatus]);

            while([(NSInputStream*)stream hasBytesAvailable]) {
                NSUInteger length = [(NSInputStream*)stream read:buffer maxLength:BUFFER_SIZE];
                NSLog(@"length=%ld", length);

                switch(length) {
                    case -1:
                        NSLog(@"Read from stream encountered an error: %@", [stream streamError]);
                        return;

                    case 0: // end of buffer
                        [_data appendBytes:buffer length:BUFFER_SIZE];
                        break;

                    default:
                        [_data appendBytes:buffer length:length];
                        break;
                }
            }
            break;

        case NSStreamEventHasSpaceAvailable:
            NSLog(@"NSStreamEventHasSpaceAvailable: ");
            break;

        case NSStreamEventOpenCompleted:
            NSLog(@"NSStreamEventOpenCompleted: %ld", [stream streamStatus]);
            break;
    }
}

@end


