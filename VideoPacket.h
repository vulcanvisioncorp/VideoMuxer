//
//  VideoPacket.h
//  VULCAM
//
//  Created by Eugene Alexeev on 14/08/2018.
//  Copyright © 2018 Vulcan Vision Corporation. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "avcodec.h"

@interface VideoPacket : NSObject

- (instancetype)init:(AVPacket *)packet;

@property (nonatomic, readonly) AVPacket *packet;
@property (nonatomic, readonly) NSInteger streamId;

@end
