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

@property (nonatomic, readonly) float progress;
@property (nonatomic, readonly) BOOL isConverting;

- (BOOL)containsOperationForFile:(NSString *)fileName;

- (void)convertInputs:(NSArray<NSString *> *)inputPaths
             toOutput:(NSString *)outputPath
             delegate:(id<VideoMuxerDelegate>)delegate
         expectedSize:(unsigned long)expectedSizeBytes;

- (void)convertInput:(NSString *)inputPath
            toFolder:(NSString *)outputsFolderPath
    outputsExtension:(NSString *)extension
            delegate:(id<VideoMuxerDelegate>)delegate
        expectedSize:(unsigned long)expectedSizeBytes
preferredOutputIdBlock:(OutputIdBlock)outputIdBlock;

- (void)convertVideosFromJSON:(NSDictionary *)jsonDict
                     toFolder:(NSString *)outputFolderPath
                     delegate:(id<VideoMuxerDelegate>)delegate;

- (void)singleConvertationInput:(NSString *)inputPath
                         output:(NSString *)outputPath
                         cookie:(NSString *)cookie
                       delegate:(id<VideoMuxerDelegate>)delegate
                   expectedSize:(unsigned long)size;

- (void)abortAllConvertations;

@end
