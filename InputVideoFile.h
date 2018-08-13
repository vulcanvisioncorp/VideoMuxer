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
@property (nonatomic, readonly) NSTimeInterval duration;

- (instancetype)initWithPath:(NSString *)filePath options:(AVDictionary *)options;

- (BOOL)readIntoPacket:(AVPacket *)packet;
- (BOOL)readIntoPacketFromFirstStream:(AVPacket *)packet;

- (AVFrame *)fetchFrameOutOfPacket:(AVPacket *)packet frameWidth:(int)width frameHeight:(int)height;

@end
