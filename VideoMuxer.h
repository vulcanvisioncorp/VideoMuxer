//
//  VideoMuxer.h
//  VULCAM
//
//  Created by Eugene Alexeev on 05/07/2017.
//  Copyright © 2017 Vulcan Vision Corporation. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "InputVideoFile.h"
#import "OutputVideoFile.h"

typedef NSNumber *(^OutputIdBlock)(NSInteger trackId);

@protocol VideoMuxerDelegate <NSObject>

- (void)muxingDidStarted:(OutputVideoFile *)file;
- (void)muxingDidFailed;
- (void)muxingDidCancelled;
- (void)muxingProgress:(float)playableProgress overallProgress:(float)progress;

- (void)videoPartCanBePlayed:(NSString *)outputPath currentProgress:(float)progress;
- (void)muxingFinished:(NSString *)outputPath size:(unsigned long)bytes;

@end

@interface VideoMuxer : NSObject

@property (weak, nonatomic) id<VideoMuxerDelegate> delegate;
@property (nonatomic, readonly) float progress;
@property (nonatomic, readonly) BOOL isConverting;

- (void)singleConvertationInput:(NSString *)inputPath
                         output:(NSString *)outputPath
                         cookie:(NSString *)cookie
                   expectedSize:(unsigned long)size;

- (void)abortAllConvertations;

@end
