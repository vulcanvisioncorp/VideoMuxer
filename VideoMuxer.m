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
#import "CommonJSONKeys.h"

static const int k_DOWNLOAD_STARTED = 50000; //in bytes

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

/**
 This method correctly works only with one-video-stream input files! Other streams will be ignored
 */
- (void)convertInputs:(NSArray<NSString *> *)inputPaths
             toOutput:(NSString *)outputPath
         expectedSize:(unsigned long)expectedSizeBytes
{
    dispatch_queue_t convertQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul);
    dispatch_async(convertQueue, ^{
        
        unsigned long readSizeBytes = 0;
        
        OutputVideoFile *outputFile = [[OutputVideoFile alloc] initWithPath:outputPath];
        NSMutableArray<InputVideoFile *> *inputFiles = [NSMutableArray new];
        for (int i = 0, max = (int)inputPaths.count; i < max; i++) {
            
            NSString *path = inputPaths[i];
            InputVideoFile *inputFile = [[InputVideoFile alloc] initWithPath:path options:NULL];
            if (!inputFile) {
                if ([self.delegate respondsToSelector:@selector(muxingDidFailed)]) {
                    [self.delegate muxingDidFailed];
                }
                return;
            }
            [inputFiles addObject:inputFile];
            [outputFile createOutputStream:inputFile.firstStream->codecpar preferredIndex:i];
        }
        [outputFile writeHeader];
        
        _isConverting = YES;
        BOOL isReading = YES;
        BOOL isReadyForReading = NO;
        NSMutableDictionary<NSNumber *, NSNumber *> *startOffsets = [NSMutableDictionary new];
        NSDate *startDate = [NSDate date];
        while (isReading)   {
            
            int successfulReadings = 0;
            for (int i = 0, max = (int)inputFiles.count; i < max; i++) {
                
                InputVideoFile *inputFile = inputFiles[i];
                
                AVPacket packet;
                BOOL success = YES;
                success = [inputFile readIntoPacketFromFirstStream:&packet];
                if (!success) {
                    NSLog(@"File probably ended!");
                    break;
                }
                readSizeBytes += packet.size;
                successfulReadings++;
                
                packet.stream_index = i;
                packet.pts = av_rescale_q(packet.pts, inputFile.firstStream->time_base, outputFile.streams[@(packet.stream_index)].stream->time_base);
                packet.dts = av_rescale_q(packet.dts, inputFile.firstStream->time_base, outputFile.streams[@(packet.stream_index)].stream->time_base);
                
                if (![startOffsets objectForKey:@(packet.stream_index)]) {
                    startOffsets[@(packet.stream_index)] = @(packet.pts);
                }
                
                packet.pts = packet.pts - startOffsets[@(packet.stream_index)].longValue;
                packet.dts = packet.dts - startOffsets[@(packet.stream_index)].longValue;
                
                success = [outputFile writePacket:&packet];
                av_packet_unref(&packet);
                if (!success) {
                    
                    if ([self.delegate respondsToSelector:@selector(muxingDidFailed)]) {
                        [self.delegate muxingDidFailed];
                    }
                    break;
                }
                
                if (readSizeBytes > k_DOWNLOAD_STARTED && !isReadyForReading) {
                    
                    isReadyForReading = YES;
                    if ([self.delegate respondsToSelector:@selector(muxingDidStarted:)]) {
                        [self.delegate muxingDidStarted:outputFile];
                    }
                }
            }
            
            if (expectedSizeBytes > 0) {
                _progress = (float)readSizeBytes/(float)expectedSizeBytes;
                if ([self.delegate respondsToSelector:@selector(muxingProgress:)]) {
                    [self.delegate muxingProgress:_progress];
                }
            }
            
            if (successfulReadings == 0) {
                break;
            }
        }
        
        [outputFile writeTrailer];
        
        NSDate *endDate = [NSDate date];
        NSTimeInterval executionTime = [endDate timeIntervalSinceDate:startDate];
        NSLog(@"Done! execution = %f", executionTime);
        
        _isConverting = NO;
        
        if ([self.delegate respondsToSelector:@selector(muxingFinished:size:)]) {
            [self.delegate muxingFinished:outputPath size:readSizeBytes];
        }
    });
}

- (void)convertInput:(NSString *)inputPath toFolder:(NSString *)outputsFolderPath outputsExtension:(NSString *)extension expectedSize:(unsigned long)expectedSizeBytes preferredOutputIdBlock:(OutputIdBlock)outputIdBlock
{
    dispatch_queue_t convertQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul);
    dispatch_async(convertQueue, ^{
        
        unsigned long readSizeBytes = 0;
        
        InputVideoFile *inputFile = [[InputVideoFile alloc] initWithPath:inputPath options:NULL];
        NSMutableDictionary<NSNumber *, OutputVideoFile *> *outputFiles = [NSMutableDictionary new];    //key is a stream index from input file.
        
        NSArray *sortedStreamIds = [[inputFile.streams allKeys] sortedArrayUsingSelector:@selector(compare:)];
        for (NSNumber *streamId in sortedStreamIds)
        {
            NSNumber *outputId = outputIdBlock != nil ? outputIdBlock(streamId.integerValue) : streamId;
            if (!outputId)
            {
                if ([self.delegate respondsToSelector:@selector(muxingDidFailed)]) {
                    [self.delegate muxingDidFailed];
                }
                return;
            }
            
            NSString *outputFilePath = @"";
            if ([extension isEqualToString:@"m3u8"]) {
                [[NSFileManager defaultManager] createDirectoryAtPath:[outputsFolderPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%d", outputId.intValue]] withIntermediateDirectories:YES attributes:nil error:nil];
                outputFilePath = [outputsFolderPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%d/%d.%@", outputId.intValue, outputId.intValue, extension]];
            } else {
                outputFilePath = [outputsFolderPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.%@", outputId.intValue, extension]];
            }
            
            OutputVideoFile *outputFile = [[OutputVideoFile alloc] initWithPath:outputFilePath];
            [outputFile createOutputStream:inputFile.streams[streamId].stream->codecpar preferredIndex:kVM_PreferredStreamId_Invalid];
            [outputFile writeHeader];
            
            outputFiles[streamId] = outputFile;
        }
        
        _isConverting = YES;
        BOOL isReading = YES;
        BOOL isReadyForReading = NO;
        unsigned long currentFrameNum = 0;
        
        while (isReading)
        {
            AVPacket packet;
            isReading = [inputFile readIntoPacket:&packet];
            if (!isReading) {
                break;
            }
            
            currentFrameNum++;
            
            OutputVideoFile *outputFile = outputFiles[@(packet.stream_index)];
            packet.pts = av_rescale_q(packet.pts, inputFile.streams[@(packet.stream_index)].stream->time_base, outputFile.firstStream->time_base);
            packet.dts = av_rescale_q(packet.dts, inputFile.streams[@(packet.stream_index)].stream->time_base, outputFile.firstStream->time_base);
            packet.stream_index = outputFile.firstStream->index;
            
            readSizeBytes += packet.size;
            BOOL success = [outputFile writePacket:&packet];
            if (!success)
            {
                NSLog(@"Error!");
                //call callback of error
                break;
            }
            
            if (readSizeBytes > k_DOWNLOAD_STARTED && !isReadyForReading) {
                
                isReadyForReading = YES;
                if ([self.delegate respondsToSelector:@selector(muxingDidStarted:)]) {
                    [self.delegate muxingDidStarted:outputFile];
                }
            }
            
            _progress = (float)(readSizeBytes/1024)/(float)(expectedSizeBytes/1024);
            if ([self.delegate respondsToSelector:@selector(muxingProgress:)]) {
                [self.delegate muxingProgress:_progress];
            }
        }
        
        for (OutputVideoFile *f in outputFiles.allValues) {
            [f writeTrailer];
        }
        NSLog(@"Done! frames = %d", currentFrameNum);
        
        _isConverting = NO;
        if ([self.delegate respondsToSelector:@selector(muxingFinished:size:)]) {
            [self.delegate muxingFinished:outputsFolderPath size:readSizeBytes];
        }
    });
}

- (void)convertVideosFromJSON:(NSDictionary *)jsonDict toFolder:(NSString *)outputFolderPath
{
    dispatch_queue_t convertQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul);
    dispatch_async(convertQueue, ^{
        
        unsigned long readSizeBytes = 0;
        
        NSString *videoOutputPath     = [outputFolderPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4", [jsonDict objectForKey:@"id"]]];
        NSString *temporaryOutputPath = [outputFolderPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_temp.mp4", [jsonDict objectForKey:@"id"]]];
        
        AVDictionary *options = nil;
        NSMutableArray<InputVideoFile *> *inputFiles = [NSMutableArray new];
        OutputVideoFile *outputFile = [[OutputVideoFile alloc] initWithPath:temporaryOutputPath];
        
        unsigned long expectedSizeBytes = 0;
        NSArray *sortedKeys = [[jsonDict[kVVCameras] allKeys] sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *camID in sortedKeys)
        {
            NSDictionary *cam = [jsonDict[kVVCameras] objectForKey:camID];
            expectedSizeBytes += [cam[kVVContentSize] integerValue];
            NSString *hlsAddr = cam[kVVMp4Stream];
            
            InputVideoFile *inputFile = [[InputVideoFile alloc] initWithPath:hlsAddr options:options];
            if (!inputFile) {
                if ([self.delegate respondsToSelector:@selector(muxingDidFailed)]) {
                    [self.delegate muxingDidFailed];
                }
                return;
            }
            [inputFiles addObject:inputFile];
            [outputFile createOutputStream:inputFile.firstStream->codecpar preferredIndex:kVM_PreferredStreamId_Invalid];
        }
        
        [outputFile writeHeader];
        
        NSTimeInterval nextSecsInterval = 2.0;
        NSTimeInterval receivedSecs = 0.0;
        
        _isConverting = YES;
        BOOL isReading = YES;
        BOOL isReadyForReading = NO;
        NSMutableDictionary<NSNumber *, NSNumber *> *startOffsets = [NSMutableDictionary new];
        NSDate *startDate = [NSDate date];
        while (isReading && !_isCancelled)
        {
            int successfulReadings = 0;
            for (int i = 0, max = (int)inputFiles.count; i < max; i++) {
                
                InputVideoFile *inputFile = inputFiles[i];
                
                AVPacket packet;
                BOOL success = YES;
                success = [inputFile readIntoPacket:&packet];
                if (!success) {
                    NSLog(@"File probably ended!"); //here maybe I should break the loop so there wouldn't be unnecessary frames muxed
                    break;
                }
                successfulReadings++;
                readSizeBytes += packet.size;
                
                packet.stream_index = i;
                packet.pts = av_rescale_q(packet.pts, [inputFile firstStream]->time_base, outputFile.streams[@(packet.stream_index)].stream->time_base);
                packet.dts = av_rescale_q(packet.dts, [inputFile firstStream]->time_base, outputFile.streams[@(packet.stream_index)].stream->time_base);
                
                if (![startOffsets objectForKey:@(packet.stream_index)]) {
                    startOffsets[@(packet.stream_index)] = @(packet.pts);
                }
                
                packet.pts = packet.pts - startOffsets[@(packet.stream_index)].longValue;
                packet.dts = packet.dts - startOffsets[@(packet.stream_index)].longValue;
                
                NSTimeInterval secs = (float)packet.pts / (outputFile.streams[@(packet.stream_index)].stream->time_base.den / outputFile.streams[@(packet.stream_index)].stream->time_base.num);
                if (secs > receivedSecs) {
                    receivedSecs = secs;
                }
                
                success = [outputFile writePacket:&packet];
                av_packet_unref(&packet);
                if (!success)   {
                    
                    if ([self.delegate respondsToSelector:@selector(muxingDidFailed)]) {
                        [self.delegate muxingDidFailed];
                    }
                    break;
                }
                
                if (readSizeBytes > k_DOWNLOAD_STARTED && !isReadyForReading) {
                    
                    isReadyForReading = YES;
                    if ([self.delegate respondsToSelector:@selector(muxingDidStarted:)]) {
                        [self.delegate muxingDidStarted:outputFile];
                    }
                }
            }
            
            _progress = (float)readSizeBytes/(float)expectedSizeBytes;
            if ([self.delegate respondsToSelector:@selector(muxingProgress:)]) {
                [self.delegate muxingProgress:_progress];
            }
            
            if (successfulReadings == 0) {
                break;
            }
            
            if (receivedSecs >= nextSecsInterval) {
                nextSecsInterval *= 2;
                
                [outputFile writeTrailer];
                [self renameFrom:outputFile.path to:videoOutputPath];
                outputFile = [self recreateOutputCopyAtPath:outputFile.path fromPath:videoOutputPath];
                
                if ([self.delegate respondsToSelector:@selector(videoPartCanBePlayed:)]) {
                    [self.delegate videoPartCanBePlayed:videoOutputPath];
                }
            }
        }
        
        if (_isCancelled) {
            [self notifyAboutAbortingOfConvertations:outputFile];
            return;
        }
        
        [outputFile writeTrailer];
        [self renameFrom:outputFile.path to:videoOutputPath];
        
        NSDate *endDate = [NSDate date];
        NSTimeInterval executionTime = [endDate timeIntervalSinceDate:startDate];
        NSLog(@"Done! execution = %f", executionTime);
        
        _isConverting = NO;
        av_dict_free(&options);
        
        if ([self.delegate respondsToSelector:@selector(muxingFinished:size:)]) {
            [self.delegate muxingFinished:outputFolderPath size:readSizeBytes];
        }
        
    });
}

- (void)singleConvertationInput:(NSString *)inputPath output:(NSString *)outputPath expectedSize:(unsigned long)size
{
    dispatch_queue_t convertQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul);
    dispatch_async(convertQueue, ^{
        
        unsigned long expectedSizeBytes = size;
        unsigned long readSizeBytes = 0;
        
        _isConverting = YES;
        AVDictionary *options = nil;
        InputVideoFile *inputFile = [[InputVideoFile alloc] initWithPath:inputPath options:options];
        OutputVideoFile *outputFile = [[OutputVideoFile alloc] initWithPath:outputPath];
        
        [outputFile createOutputStreamsForFile:inputFile];
        [outputFile writeHeader];
        
        AVPacket *packet = av_malloc(sizeof(AVPacket));
        BOOL isReading = YES;
        int counter = 0;
        NSDate *startDate = [NSDate date];
        unsigned long currentFrameNum = 0;
        
        BOOL isReadyForReading = NO;
        NSMutableDictionary<NSNumber *, NSNumber *> *startOffsets = [NSMutableDictionary new];
        while (isReading)   {
            
            counter++;
            isReading = [inputFile readIntoPacket:packet];
            if (!isReading) {
                break;
            }
            
            currentFrameNum++;
            packet->pts = av_rescale_q(packet->pts, inputFile.streams[@(packet->stream_index)].stream->time_base, outputFile.streams[@(packet->stream_index)].stream->time_base);
            packet->dts = av_rescale_q(packet->dts, inputFile.streams[@(packet->stream_index)].stream->time_base, outputFile.streams[@(packet->stream_index)].stream->time_base);
            
            if (![startOffsets objectForKey:@(packet->stream_index)]) {
                startOffsets[@(packet->stream_index)] = @(packet->pts);
            }
            
            packet->pts = packet->pts - startOffsets[@(packet->stream_index)].longValue;;
            packet->dts = packet->dts - startOffsets[@(packet->stream_index)].longValue;;
            
            readSizeBytes += packet->size;
            BOOL success = [outputFile writePacket:packet];
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
            
            _progress = (float)(readSizeBytes/1024)/(float)(expectedSizeBytes/1024);
            if ([self.delegate respondsToSelector:@selector(muxingProgress:)]) {
                [self.delegate muxingProgress:_progress];
            }
        }
        
        av_packet_unref(packet);
        [outputFile writeTrailer];
        
        NSDate *endDate = [NSDate date];
        NSTimeInterval executionTime = [endDate timeIntervalSinceDate:startDate];
        NSLog(@"Done! frames = %d, execution = %f", counter, executionTime);
        
        _isConverting = NO;
        av_dict_free(&options);
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
    _isCancelled = YES;
}

- (void)notifyAboutAbortingOfConvertations:(OutputVideoFile *)videoFile
{
    _isCancelled = NO;
    if ([self.delegate respondsToSelector:@selector(muxingDidCancelled)]) {
        [self.delegate muxingDidCancelled];
    }
}

@end
