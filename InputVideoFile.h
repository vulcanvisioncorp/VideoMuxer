//
//  InputVideoFile.h
//  VULCAM
//
//  Created by Eugene Alexeev on 05/07/2017.
//  Copyright © 2017 Vulcan Vision Corporation. All rights reserved.
//

#import "VideoFile.h"
#import <Foundation/Foundation.h>


@interface InputVideoFile : VideoFile
{
    
}

@property (nonatomic, readonly) AVCodec *codec;
@property (nonatomic, readonly) AVCodecParameters *codecParams;

- (instancetype)initWithPath:(NSString *)filePath options:(AVDictionary *)options;

- (BOOL)readIntoPacket:(AVPacket *)packet;
- (BOOL)readIntoPacketFromFirstStream:(AVPacket *)packet;

@end
