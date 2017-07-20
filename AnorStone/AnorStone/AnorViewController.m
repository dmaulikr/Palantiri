//
//  AnorViewController.m
//  AnorStone
//
//  Created by Paul Schifferer on 18/7/17.
//  Copyright © 2017 Pilgrimage Software. All rights reserved.
//

#import "AnorViewController.h"
@import CoreGraphics;
@import CoreFoundation;
#include <sys/socket.h>
#include <netinet/in.h>


static NSInteger PORT_NUMBER = 11924;
static NSInteger BUFFER_SIZE = 1024;

void acceptCallback(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
    NSLog(@"s=%@, type=%ld, data=%p, info=%@", s, type, data, info);

    // setup stream
    //    CFSocketNativeHandle handle = CFSocketGetNative(s);
    if(type == kCFSocketAcceptCallBack) {
        CFSocketNativeHandle handle = (CFSocketNativeHandle)data;
        NSLog(@"handle=%ld", (long)handle);

        //    CFSocketRef c = CFSocketCreateWithNative(kCFAllocatorDefault, handle, kCFSocketReadCallBack, readCallback, info);
        CFReadStreamRef input;
        CFWriteStreamRef output;
        CFStreamCreatePairWithSocket(kCFAllocatorDefault,
                                     handle,
                                     &input,
                                     &output);
        NSLog(@"input=%@, output=%@", input, output);
        //    CFSocketContext context;
        //    CFSocketGetContext(s, &context);
        //        CFReadStreamSetClient(input, kCFStreamEventNone, NULL, NULL);
        NSInputStream* inputStream = (NSInputStream*)CFBridgingRelease(input);
        NSOutputStream* outputStream = (NSOutputStream*)CFBridgingRelease(output);
        AnorViewController* vc = (__bridge AnorViewController*)info;
        [vc setupInputStream:inputStream
                outputStream:outputStream];

        //        CFSocketEnableCallBacks(s, kCFSocketReadCallBack);
    }
}

//void readCallback(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {

@implementation AnorViewController {
    
@private
    CFSocketRef _socket;
    NSInputStream* _inputStream;
    NSOutputStream* _outputStream;
    NSMutableData* _data;
    //    dispatch_source_t _acceptSource;
    //    dispatch_source_t _clientSource;

}

- (void)viewDidLoad {
    [super viewDidLoad];

    _data = [NSMutableData new];

    [self setupListener];
}

- (void)setupListener {

    CFSocketContext context = { 0, (__bridge void*)(self), NULL, NULL, NULL };
    _socket = CFSocketCreate(kCFAllocatorDefault,
                             PF_INET,
                             SOCK_STREAM,
                             IPPROTO_TCP,
                             kCFSocketAcceptCallBack,
                             acceptCallback,
                             &context);

    //    int s = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);

    struct sockaddr_in sin;
    
    memset(&sin, 0, sizeof(sin));
    sin.sin_len = sizeof(sin);
    sin.sin_family = AF_INET;
    sin.sin_port = htons(PORT_NUMBER);
    sin.sin_addr.s_addr = INADDR_ANY;

    //    if(bind(s, (struct sockaddr *)&sin, sizeof(sin)) < 0) {
    //        // Handle the error.
    //    }
    //
    //    errno_t err = listen(s, 1);
    //
    //    _acceptSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, s, 0, dispatch_get_main_queue());
    //    dispatch_source_set_event_handler(_acceptSource, ^{
    //        struct sockaddr_in newsin;
    //        size_t newsin_size;
    //        int newsock = accept(s, (struct sockaddr*)&newsin, &newsin_size);
    //
    //        _clientSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, newsock, 0, dispatch_get_main_queue());
    //        setsockopt(newsock, 0, SO_NOSIGPIPE, 1, 1);
    //        dispatch_source_set_event_handler(_clientSource, ^{
    //            dispatch_async(dispatch_get_main_queue(), ^{
    //                char buf[1024];
    //                ssize_t len = read(newsock, buf, 1024);
    //            });
    //        });
    //    });
    CFDataRef data = CFDataCreate(kCFAllocatorDefault, (UInt8*)&sin, sizeof(sin));

    CFSocketSetAddress(_socket, data);
    CFRelease(data);

    CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _socket, 0);

    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
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

- (void)setupInputStream:(NSInputStream*)inputStream outputStream:(NSOutputStream*)outputStream {

    dispatch_async(dispatch_get_main_queue(), ^{
        _inputStream = inputStream;
        _inputStream.delegate = self;

        _outputStream = outputStream;
        _outputStream.delegate = self;

        [_inputStream scheduleInRunLoop:[NSRunLoop mainRunLoop]
                                forMode:NSDefaultRunLoopMode];
        [_inputStream open];

        [_outputStream scheduleInRunLoop:[NSRunLoop mainRunLoop]
                                 forMode:NSDefaultRunLoopMode];
        [_outputStream open];
    });
}

@end


