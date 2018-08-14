//
//  VideoPacket.m
//  VULCAM
//
//  Created by Eugene Alexeev on 14/08/2018.
//  Copyright © 2018 Vulcan Vision Corporation. All rights reserved.
//

#import "VideoPacket.h"

@implementation VideoPacket

- (instancetype)init:(AVPacket *)packet
{
    self = [super init];
    if (self) {
        _packet = packet;
        _streamId = packet->stream_index;
    }
    
    return self;
}

@end
