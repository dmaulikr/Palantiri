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

void acceptCallback(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info) {
    // setup stream
    CFSocketNativeHandle handle = (CFSocketNativeHandle)data;
    CFReadStreamRef input;
    CFStreamCreatePairWithSocket(kCFAllocatorDefault,
                                 handle,
                                 &input,
                                 NULL);
    CFSocketContext context;
    CFSocketGetContext(s, &context);
    NSInputStream* stream = (NSInputStream*)CFBridgingRelease(input);
    AnorViewController* vc = (__bridge AnorViewController*)context.info;
    stream.delegate = vc;
    vc.inputStream = stream;
}

@implementation AnorViewController {
    
@private
    CFSocketRef _socket;

}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self setupListener];
}

- (void)setupListener {

    _socket = CFSocketCreate(kCFAllocatorDefault,
                             PF_INET,
                             SOCK_STREAM,
                             IPPROTO_TCP,
                             kCFSocketAcceptCallBack,
                             acceptCallback,
                             NULL);
    CFSocketContext context;
    CFSocketGetContext(_socket, &context);
    context.info = (__bridge void*)self;

    struct sockaddr_in sin;
    
    memset(&sin, 0, sizeof(sin));
    sin.sin_len = sizeof(sin);
    sin.sin_family = AF_INET;
    sin.sin_port = htons(PORT_NUMBER);
    sin.sin_addr.s_addr = INADDR_ANY;
    
    CFDataRef data = CFDataCreate(kCFAllocatorDefault, (UInt8*)&sin, sizeof(sin));
    
    CFSocketSetAddress(_socket, data);
    CFRelease(data);
    
    CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _socket, 0);
    
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode {
    NSLog(@"%@: %@, %ld", NSStringFromSelector(_cmd), stream, eventCode);

    // TODO
}

@end


