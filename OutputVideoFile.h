//
//  OutputVideoFile.h
//  VULCAM
//
//  Created by Eugene Alexeev on 05/07/2017.
//  Copyright © 2017 Vulcan Vision Corporation. All rights reserved.
//

#import "VideoFile.h"
#import "InputVideoFile.h"
#import <Foundation/Foundation.h>

@interface OutputVideoFile : VideoFile
{
    
}

@property (nonatomic, readonly) AVFormatContext *formatContext;

- (void)createOutputStreamsForFile:(InputVideoFile *)file;
- (void)createOutputStream:(AVCodecParameters *)streamParams preferredIndex:(int)streamIndex customKey:(NSNumber *)customKey;

- (BOOL)writeHeader;
- (BOOL)writePacket:(AVPacket *)packet;
- (BOOL)writeFrame:(AVFrame *)frame streamIndex:(int)stream_index;
- (void)writeTrailer;


@end
