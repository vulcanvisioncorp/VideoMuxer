//
//  VideoFile.h
//  VULCAM
//
//  Created by Eugene Alexeev on 03/07/2017.
//  Copyright © 2017 Vulcan Vision Corporation. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "VideoStream.h"
#import "avformat.h"
#import "avcodec.h"
#import "swscale.h"
#import "imgutils.h"

static const NSInteger kVM_PreferredStreamId_Invalid = -1;

@interface VideoFile : NSObject
{
    AVFormatContext *_pFormatCtx;
    NSString *_filePath;
    NSMutableDictionary<NSNumber *, VideoStream *> *_streams;
    AVStream *_firstStream;
}

@property (nonatomic, readonly) NSString *path;
@property (nonatomic, readonly) NSMutableDictionary<NSNumber *, VideoStream *> *streams;
@property (nonatomic, readonly) AVStream *firstStream;

- (instancetype)initWithPath:(NSString *)filePath;
- (void)raiseExceptionWithMessage:(NSString *)msg;

- (void)clear;

@end
