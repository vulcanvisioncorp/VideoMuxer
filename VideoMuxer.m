//
//  VideoMuxer.m
//  VULCAM
//
//  Created by Eugene Alexeev on 05/07/2017.
//  Copyright © 2017 Vulcan Vision Corporation. All rights reserved.
//


/* ****
 
 For the time being the only problem in new video algorithm is - playing video while it's downloading. I thought writing own player will solve this issue
 but apparently it's not enough to deal with that.
 
 mp4 is the file format which has trail with indices on it (it calls "moov" part). Without that part ffmpeg denies reading the file.
 
 What we can do to solve this issue:
 1) instead of creating mp4 from HLS iPod streams, we can create another LOCAL HLS stream with muxed streams. In that way we should be able to play received video data
 without waiting for trails
 2) and once local HLS stream is downloaded and converted, we could convert that into mp4 in back thread so user won't even notice it. 
 
 From the first point of view it could be a hard thing to implement but it's not. Converter works very very fast, and converting local file into another format is the matter of 
 1-3 secs.
 
 */

#import "VideoMuxer.h"

@interface VideoMuxer()
{
    BOOL _isCancelled;
}

@end

@implementation VideoMuxer

/* NOTE: This method is muxing few videofiles into one. That's what we want to achieve in future - just one videofile.
 VUVPlayer knows how to work with few streams, but you need to consider that videofiles should have SAME settings all the time*/

- (instancetype)init
{
    self = [super init];
    if (self) {
        _isConverting = NO;
        _isCancelled = NO;
    }
    
    return self;
}

- (void)singleConvertationInput:(NSString *)inputPath output:(NSString *)outputPath cookie:(NSString *)cookie expectedSize:(unsigned long)size
{
    dispatch_queue_t convertQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul);
    dispatch_async(convertQueue, ^{
        
        unsigned long expectedSizeBytes = size;
        unsigned long readSizeBytes = 0;
        
        self->_isConverting = YES;
        
        AVDictionary *options = NULL;
        if (cookie) {
            NSString *cookieString = [NSString stringWithFormat:@"Cookie: %@", cookie];
            NSDictionary *headersDict = [NSDictionary dictionaryWithObject:cookieString forKey:@"headers"];
            options = [self createAVFormatOptionsOutOfDict:headersDict];
        }
        
        NSString *temporaryOutputPath = [[outputPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_temp.mp4", [[outputPath lastPathComponent] stringByDeletingPathExtension]]];
        
        InputVideoFile *inputFile = [[InputVideoFile alloc] initWithPath:inputPath options:options];
        OutputVideoFile *outputFile = [[OutputVideoFile alloc] initWithPath:temporaryOutputPath];
        
        [outputFile createOutputStreamsForFile:inputFile];
        [outputFile writeHeader];
        
        AVPacket *packet = av_malloc(sizeof(AVPacket));
        BOOL isReading = YES;
        int counter = 0;
        NSDate *startDate = [NSDate date];
        unsigned long currentFrameNum = 0;
        
        NSTimeInterval nextSecsInterval = 2.0;
        NSTimeInterval receivedSecs = 0.0;
        
        NSTimeInterval playableProgress = 0.0f;
        BOOL isReadyForReading = NO;
        NSMutableDictionary<NSNumber *, NSNumber *> *startOffsets = [NSMutableDictionary new];
        int attemptsToRead = 0;
        int maxAttemptsToRead = 5;
        while (isReading && !self->_isCancelled)
        {
            counter++;
            BOOL success = [inputFile readIntoPacket:packet];
            if (!success) {
                attemptsToRead++;
                if (attemptsToRead >= maxAttemptsToRead) {
                    break;
                } else {
                    NSLog(@"Attempt = %d", attemptsToRead);
                    continue;
                }
            }
            attemptsToRead = 0;
            
            currentFrameNum++;
            packet->pts = av_rescale_q(packet->pts, inputFile.streams[@(packet->stream_index)].stream->time_base, outputFile.streams[@(packet->stream_index)].stream->time_base);
            packet->dts = av_rescale_q(packet->dts, inputFile.streams[@(packet->stream_index)].stream->time_base, outputFile.streams[@(packet->stream_index)].stream->time_base);
            
            if (![startOffsets objectForKey:@(packet->stream_index)]) {
                startOffsets[@(packet->stream_index)] = @(packet->pts);
            }
            
            packet->pts = packet->pts - startOffsets[@(packet->stream_index)].longValue;;
            packet->dts = packet->dts - startOffsets[@(packet->stream_index)].longValue;;
            
            NSTimeInterval secs = (float)packet->pts / (outputFile.streams[@(packet->stream_index)].stream->time_base.den / outputFile.streams[@(packet->stream_index)].stream->time_base.num);
            if (secs > receivedSecs) {
                receivedSecs = secs;
            }
            
            readSizeBytes += packet->size;
            success = [outputFile writePacket:packet];
            if (!success)
            {
                av_dict_free(&options);
                NSLog(@"Error!");
                //call callback of error
                break;
            }
            
            if (readSizeBytes > 50000 && !isReadyForReading) {
                
                isReadyForReading = YES;
                if ([self.delegate respondsToSelector:@selector(muxingDidStarted:)]) {
                    [self.delegate muxingDidStarted:outputFile];
                }
            }
            
            self->_progress = (float)(readSizeBytes/1024)/(float)(expectedSizeBytes/1024);
            if ([self.delegate respondsToSelector:@selector(muxingProgress:overallProgress:)]) {
                [self.delegate muxingProgress:playableProgress overallProgress:self->_progress];
            }
            
            if (receivedSecs >= nextSecsInterval) {
                nextSecsInterval *= 2;
                
                [outputFile writeTrailer];
                [self renameFrom:outputFile.path to:outputPath];
                outputFile = [self recreateOutputCopyAtPath:outputFile.path fromPath:outputPath];
                
                playableProgress = self->_progress;
                if ([self.delegate respondsToSelector:@selector(videoPartCanBePlayed:currentProgress:)]) {
                    [self.delegate videoPartCanBePlayed:outputPath currentProgress:self->_progress];
                }
            }
            av_packet_unref(packet);
        }
        
        if (self->_isCancelled) {
            self->_isConverting = NO;

            if ([[NSFileManager defaultManager] fileExistsAtPath:temporaryOutputPath]) {
                [[NSFileManager defaultManager] removeItemAtPath:temporaryOutputPath error:nil];
            }
            
            if ([[NSFileManager defaultManager] fileExistsAtPath:outputPath]) {
                [[NSFileManager defaultManager] removeItemAtPath:outputPath error:nil];
            }
            
            [self notifyAboutAbortingOfConvertations:outputFile];
            return;
        }
        
        [outputFile writeTrailer];
        [self renameFrom:outputFile.path to:outputPath];
        
        NSDate *endDate = [NSDate date];
        NSTimeInterval executionTime = [endDate timeIntervalSinceDate:startDate];
        NSLog(@"Done! frames = %d, execution = %f", counter, executionTime);
        
        self->_isConverting = NO;
        //av_dict_free(&options);
        if ([self.delegate respondsToSelector:@selector(muxingFinished:size:)]) {
            [self.delegate muxingFinished:outputPath size:readSizeBytes];
        }
    });
}

- (OutputVideoFile *)recreateOutputCopyAtPath:(NSString *)outputPath fromPath:(NSString *)inputPath
{
    InputVideoFile *inputFile = [[InputVideoFile alloc] initWithPath:inputPath options:NULL];
    OutputVideoFile *newFile = [[OutputVideoFile alloc] initWithPath:outputPath];
    
    [newFile createOutputStreamsForFile:inputFile];
    [newFile writeHeader];
    
    AVPacket *packet = av_malloc(sizeof(AVPacket));
    BOOL isReading = YES;
    while (isReading)
    {
        isReading = [inputFile readIntoPacket:packet];
        if (!isReading) {
            break;
        }
        
        BOOL success = [newFile writePacket:packet];
        if (!success) {
            isReading = NO;
            NSLog(@"Error!");
            //call callback of error
            break;
        }
    }
    
    return newFile;
}

- (void)renameFrom:(NSString *)fromPath to:(NSString *)toPath
{
    if ([[NSFileManager defaultManager] fileExistsAtPath:toPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:toPath error:nil];
    }
    
    NSError *err = nil;
    [[NSFileManager defaultManager] moveItemAtPath:fromPath toPath:toPath error:&err];
    if (err) {
        NSLog(@"Error: %@", err.description);
    }
}

- (void)abortAllConvertations
{
    if (_isConverting) {
        _isCancelled = YES;
    }
}

- (void)notifyAboutAbortingOfConvertations:(OutputVideoFile *)videoFile
{
    _isCancelled = NO;
    if ([self.delegate respondsToSelector:@selector(muxingDidCancelled)]) {
        [self.delegate muxingDidCancelled];
    }
}

- (AVDictionary *)createAVFormatOptionsOutOfDict:(NSDictionary *)dict
{
    AVDictionary *options = NULL;
    for (NSString *key in dict.allKeys) {
        av_dict_set(&options, [key UTF8String], [[dict objectForKey:key] UTF8String], 0);
    }
    
    return options;
}

@end
