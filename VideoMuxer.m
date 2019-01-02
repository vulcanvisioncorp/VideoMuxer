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
#import "MuxingOperation.h"
#import "VideoPacket.h"

static const int k_DOWNLOAD_STARTED = 50000; //in bytes

static NSString *const kVVCameras = @"cameras";
static NSString *const kVVMp4Stream = @"mp4Stream";
static NSString *const kVVContentSize = @"contentSize";

@interface VideoMuxer()
{
    NSMutableArray<MuxingOperation *> *_operations;    //here will be MuxingOperationState enum values. I'm using NSNumber * just because NSMutableArray can not store simple enums
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
        _operations = [NSMutableArray new];
    }
    
    return self;
}

- (void)cancelConvertation:(NSArray<NSString *> *)pathsToClean delegate:(id<VideoMuxerDelegate>)delegate
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *p in pathsToClean) {
        if ([fileManager fileExistsAtPath:p]) {
            [fileManager removeItemAtPath:p error:nil];
        }
    }
    
    [self notifyAboutAbortingOfConvertations:delegate];
}

//MARK: - Muxing operations handling
- (MuxingOperation *)createMuxingOperationForFile:(NSString *)fileName
{
    MuxingOperation *newOperation = [[MuxingOperation alloc] init:MuxingOperationStateReading fileName:fileName];
    [_operations addObject:newOperation];
    
    return newOperation;
}

- (void)removeMuxingOperation:(MuxingOperation *)operation
{
    [_operations removeObject:operation];
    _isConverting = _operations.count > 0;
}

- (BOOL)containsOperationForFile:(NSString *)fileName
{
    for (MuxingOperation *op in _operations) {
        if ([op.fileName isEqualToString:fileName]) {
            return YES;
        }
    }
    
    return NO;
}

//MARK: - Dispatch delegates
- (void)dispatchMuxingDidStarted:(OutputVideoFile *)file delegate:(id<VideoMuxerDelegate>) delegate
{
    if (!delegate) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([delegate respondsToSelector:@selector(muxingDidStarted:)]) {
            [delegate muxingDidStarted:file.path];
        }
    });
}

- (void)dispatchMuxingDidFailed:(id<VideoMuxerDelegate>) delegate
{
    if (!delegate) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([delegate respondsToSelector:@selector(muxingDidFailed)]) {
            [delegate muxingDidFailed];
        }
    });
}

- (void)dispatchMuxingDidCancelled:(id<VideoMuxerDelegate>) delegate
{
    if (!delegate) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([delegate respondsToSelector:@selector(muxingDidCancelled)]) {
            [delegate muxingDidCancelled];
        }
    });
}

- (void)dispatchMuxingProgress:(float)playableProgress overallProgress:(float)progress operation:(MuxingOperation *)operation delegate:(id<VideoMuxerDelegate>) delegate
{
    if (!delegate) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([delegate respondsToSelector:@selector(muxingProgress:overallProgress:)] && operation.state == MuxingOperationStateReading) {
            [delegate muxingProgress:playableProgress overallProgress:self->_progress];
        }
    });
}

- (void)dispatchVideoPartCanBePlayed:(NSString *)outputPath currentProgress:(float)progress delegate:(id<VideoMuxerDelegate>) delegate
{
    if (!delegate) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([delegate respondsToSelector:@selector(videoPartCanBePlayed:currentProgress:)]) {
            [delegate videoPartCanBePlayed:outputPath currentProgress:self->_progress];
        }
    });
}

- (void)dispatchMuxingFinished:(NSString *)outputPath size:(unsigned long)bytes delegate:(id<VideoMuxerDelegate>) delegate
{
    if (!delegate) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([delegate respondsToSelector:@selector(muxingFinished:size:)]) {
            [delegate muxingFinished:outputPath size:bytes];
        }
    });
}

//MARK: - Convertation methods
/**
 This method correctly works only with one-video-stream input files! Other streams will be ignored
 */
- (void)convertInputs:(NSArray<NSString *> *)inputPaths
             toOutput:(NSString *)outputPath
             delegate:(id<VideoMuxerDelegate>)delegate
         expectedSize:(unsigned long)expectedSizeBytes
{
    MuxingOperation *operation = [self createMuxingOperationForFile:outputPath.lastPathComponent.stringByDeletingPathExtension];
    dispatch_queue_t convertQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul);
    dispatch_async(convertQueue, ^{
        
        unsigned long readSizeBytes = 0;
        
        OutputVideoFile *outputFile = [[OutputVideoFile alloc] initWithPath:outputPath];
        NSMutableArray<InputVideoFile *> *inputFiles = [NSMutableArray new];
        for (int i = 0, max = (int)inputPaths.count; i < max; i++) {
            
            NSString *path = inputPaths[i];
            InputVideoFile *inputFile = [[InputVideoFile alloc] initWithPath:path options:NULL];
            if (!inputFile) {
                [self dispatchMuxingDidFailed:delegate];
                return;
            }
            [inputFiles addObject:inputFile];
            [outputFile createOutputStream:inputFile.firstStream->codecpar preferredIndex:i];
        }
        [outputFile writeHeader];
        
        self->_isConverting = YES;
        BOOL isReadyForReading = NO;
        NSMutableDictionary<NSNumber *, NSNumber *> *startOffsets = [NSMutableDictionary new];
        NSDate *startDate = [NSDate date];
        while (operation.state == MuxingOperationStateReading)   {
            
            int successfulReadings = 0;
            for (int i = 0, max = (int)inputFiles.count; i < max; i++) {
                
                InputVideoFile *inputFile = inputFiles[i];
                
                AVPacket packet;
                BOOL success = YES;
                success = [inputFile readIntoPacketFromFirstStream:&packet];
                if (!success) {
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
                    [self dispatchMuxingDidFailed:delegate];
                    break;
                }
                
                if (readSizeBytes > k_DOWNLOAD_STARTED && !isReadyForReading) {
                    
                    isReadyForReading = YES;
                    [self dispatchMuxingDidStarted:outputFile delegate:delegate];
                }
            }
            
            if (expectedSizeBytes > 0) {
                self->_progress = (float)readSizeBytes/(float)expectedSizeBytes;
                [self dispatchMuxingProgress:0.0 overallProgress:self->_progress operation:operation delegate:delegate];
            }
            
            if (successfulReadings == 0) {
                operation.state = MuxingOperationStateSuccess;
                break;
            }
        }
        
        switch (operation.state) {
            case MuxingOperationStateSuccess:
            {
                [outputFile writeTrailer];
                
                NSDate *endDate = [NSDate date];
                NSTimeInterval executionTime = [endDate timeIntervalSinceDate:startDate];
                NSLog(@"Done! execution = %f", executionTime);
                
                [self dispatchMuxingFinished:outputPath size:readSizeBytes delegate:delegate];
            }
                break;
            case MuxingOperationStateCancelled:
                [self cancelConvertation:@[outputPath] delegate:delegate];
                break;
            default:
                break;
        }
        
        [self removeMuxingOperation:operation];
    });
}

- (void)convertInput:(NSString *)inputPath
            toFolder:(NSString *)outputsFolderPath
    outputsExtension:(NSString *)extension
            delegate:(id<VideoMuxerDelegate>)delegate
        expectedSize:(unsigned long)expectedSizeBytes
preferredOutputIdBlock:(OutputIdBlock)outputIdBlock
{
    MuxingOperation *operation = [self createMuxingOperationForFile:outputsFolderPath.lastPathComponent];
    dispatch_queue_t convertQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul);
    dispatch_async(convertQueue, ^{
        
        unsigned long readSizeBytes = 0;
        
        InputVideoFile *inputFile = [[InputVideoFile alloc] initWithPath:inputPath options:NULL];
        NSMutableDictionary<NSNumber *, OutputVideoFile *> *outputFiles = [NSMutableDictionary new];    //key is a stream index from input file.
        
        NSArray *sortedStreamIds = [[inputFile.streams allKeys] sortedArrayUsingSelector:@selector(compare:)];
        for (NSNumber *streamId in sortedStreamIds)
        {
            NSNumber *outputId = outputIdBlock != nil ? outputIdBlock(streamId.integerValue) : streamId;
            if (!outputId) {
                [self dispatchMuxingDidFailed:delegate];
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
        
        self->_isConverting = YES;
        BOOL isReadyForReading = NO;
        unsigned long currentFrameNum = 0;
        
        while (operation.state == MuxingOperationStateReading)
        {
            AVPacket packet;
            BOOL success = [inputFile readIntoPacket:&packet];
            if (!success) {
                operation.state = MuxingOperationStateSuccess;
                break;
            }
            
            currentFrameNum++;
            
            OutputVideoFile *outputFile = outputFiles[@(packet.stream_index)];
            packet.pts = av_rescale_q(packet.pts, inputFile.streams[@(packet.stream_index)].stream->time_base, outputFile.firstStream->time_base);
            packet.dts = av_rescale_q(packet.dts, inputFile.streams[@(packet.stream_index)].stream->time_base, outputFile.firstStream->time_base);
            packet.stream_index = outputFile.firstStream->index;
            
            readSizeBytes += packet.size;
            success = [outputFile writePacket:&packet];
            if (!success)
            {
                NSLog(@"Error!");
                [self dispatchMuxingDidFailed:delegate];
                break;
            }
            
            if (readSizeBytes > k_DOWNLOAD_STARTED && !isReadyForReading) {
                
                isReadyForReading = YES;
                [self dispatchMuxingDidStarted:outputFile delegate:delegate];
            }
            
            if (expectedSizeBytes > 0) {
                self->_progress = (float)(readSizeBytes/1024)/(float)(expectedSizeBytes/1024);
                [self dispatchMuxingProgress:0.0 overallProgress:self->_progress operation:operation delegate:delegate];
            }
        }
        
        switch (operation.state) {
            case MuxingOperationStateSuccess:
            {
                for (OutputVideoFile *f in outputFiles.allValues) {
                    [f writeTrailer];
                }
                [self dispatchMuxingFinished:outputsFolderPath size:readSizeBytes delegate:delegate];
            }
                break;
            case MuxingOperationStateCancelled:
                [self cancelConvertation:@[outputsFolderPath] delegate:delegate];
                break;
            default:
                break;
        }
        
        [self removeMuxingOperation:operation];
    });
}

- (void)convertVideosFromJSON:(NSDictionary *)jsonDict
                     toFolder:(NSString *)outputFolderPath
                     delegate:(id<VideoMuxerDelegate>)delegate
{
    [self convertVideosFromJSON:jsonDict toFolder:outputFolderPath delegate:delegate deleteLocalInputs:false];
}

- (void)convertVideosFromJSON:(NSDictionary *)jsonDict
                     toFolder:(NSString *)outputFolderPath
                     delegate:(id<VideoMuxerDelegate>)delegate
            deleteLocalInputs:(BOOL)deleteLocalInputs
{
    MuxingOperation *operation = [self createMuxingOperationForFile:[jsonDict objectForKey:@"id"]];
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
                [self dispatchMuxingDidFailed:delegate];
                return;
            }
            [inputFiles addObject:inputFile];
            [outputFile createOutputStream:inputFile.firstStream->codecpar preferredIndex:kVM_PreferredStreamId_Invalid];
        }
        
        [outputFile writeHeader];
        
        NSTimeInterval playableProgress = 0.0;
        NSTimeInterval nextSecsInterval = 2.0;
        NSTimeInterval receivedSecs = 0.0;
        
        self->_isConverting = YES;
        BOOL isReadyForReading = NO;
        NSMutableDictionary<NSNumber *, NSNumber *> *startOffsets = [NSMutableDictionary new];
        NSDate *startDate = [NSDate date];
        while (operation.state == MuxingOperationStateReading)
        {
            int successfulReadings = 0;
            for (int i = 0, max = (int)inputFiles.count; i < max; i++)
            {
                InputVideoFile *inputFile = inputFiles[i];
                
                AVPacket packet;
                BOOL success = YES;
                success = [inputFile readIntoPacket:&packet];
                if (!success) {
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
                if (!success)   {
                    [self dispatchMuxingDidFailed:delegate];
                    break;
                }
                av_packet_unref(&packet);
                
                if (readSizeBytes > k_DOWNLOAD_STARTED && !isReadyForReading) {
                    isReadyForReading = YES;
                    [self dispatchMuxingDidStarted:outputFile delegate:delegate];
                }
            }
            
            if (expectedSizeBytes > 0) {
                self->_progress = (float)readSizeBytes/(float)expectedSizeBytes;
                [self dispatchMuxingProgress:playableProgress overallProgress:self->_progress operation:operation delegate:delegate];
            }
            
            if (successfulReadings == 0) {
                operation.state = MuxingOperationStateSuccess;
                break;
            }
            
            if (receivedSecs >= nextSecsInterval) {
                nextSecsInterval *= 2;
                
                [outputFile writeTrailer];
                [self renameFrom:outputFile.path to:videoOutputPath];
                outputFile = [self recreateOutputCopyAtPath:outputFile.path fromPath:videoOutputPath];
                
                playableProgress = self->_progress;
                [self dispatchVideoPartCanBePlayed:videoOutputPath currentProgress:playableProgress delegate:delegate];
            }
        }
        
        switch (operation.state) {
            case MuxingOperationStateSuccess:
            {
                NSLog(@"This is clearly SUCCESS!");
                [outputFile writeTrailer];
                [self renameFrom:outputFile.path to:videoOutputPath];
                
                NSDate *endDate = [NSDate date];
                NSTimeInterval executionTime = [endDate timeIntervalSinceDate:startDate];
                float megabytes = readSizeBytes / 1000.0f / 1000.0f;
                NSLog(@"Done! execution = %f, size = %f Mb", executionTime, megabytes);
                
                if (options) {
                    av_dict_free(&options);
                }
                
                [self dispatchMuxingFinished:outputFolderPath size:readSizeBytes delegate:delegate];
                
                if (deleteLocalInputs) {
                    for(InputVideoFile *vf in inputFiles) {
                        if ([[NSFileManager defaultManager] fileExistsAtPath:vf.path]) {
                            [[NSFileManager defaultManager] removeItemAtPath:vf.path error:nil];
                        }
                    }
                }
            }
                break;
            case MuxingOperationStateCancelled:
                NSLog(@"Got cancelled!");
                [self cancelConvertation:@[temporaryOutputPath, videoOutputPath] delegate:delegate];
                break;
            default:
                break;
        }
        
        [self removeMuxingOperation:operation];
    });
}

- (void)singleConvertationInput:(NSString *)inputPath
                         output:(NSString *)outputPath
                         cookie:(NSString *)cookie
                       delegate:(id<VideoMuxerDelegate>)delegate
                   expectedSize:(unsigned long)size
{
    MuxingOperation *operation = [self createMuxingOperationForFile:outputPath.lastPathComponent.stringByDeletingPathExtension];
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
        BOOL success = [outputFile writeHeader];
        if (!success) {
            [self dispatchMuxingDidFailed:delegate];
            return;
        }
        
        AVPacket *packet = av_malloc(sizeof(AVPacket));
        int counter = 0;
        NSDate *startDate = [NSDate date];
        unsigned long currentFrameNum = 0;
        
        NSTimeInterval nextSecsInterval = 2.0;
        NSTimeInterval receivedSecs = 0.0;
        
        NSTimeInterval playableProgress = 0.0f;
        BOOL isReadyForReading = NO;
        NSMutableDictionary<NSNumber *, NSNumber *> *startOffsets = [NSMutableDictionary new];
        while (operation.state == MuxingOperationStateReading)
        {
            counter++;
            success = [inputFile readIntoPacket:packet];
            if (!success) {
                operation.state = MuxingOperationStateSuccess;
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
            
            NSTimeInterval secs = (float)packet->pts / (outputFile.streams[@(packet->stream_index)].stream->time_base.den / outputFile.streams[@(packet->stream_index)].stream->time_base.num);
            if (secs > receivedSecs) {
                receivedSecs = secs;
            }
            
            readSizeBytes += packet->size;
            success = [outputFile writePacket:packet];
            if (!success)
            {
                av_dict_free(&options);
                [self dispatchMuxingDidFailed:delegate];
                break;
            }
            
            if (!isReadyForReading) {
                isReadyForReading = YES;
                [self dispatchMuxingDidStarted:outputFile delegate:delegate];
            }
            
            self->_progress = (float)(readSizeBytes/1024)/(float)(expectedSizeBytes/1024);
            [self dispatchMuxingProgress:playableProgress overallProgress:self->_progress operation:operation delegate:delegate];
            
            if (receivedSecs >= nextSecsInterval) {
                nextSecsInterval *= 2;
                
                [outputFile writeTrailer];
                [self renameFrom:outputFile.path to:outputPath];
                outputFile = [self recreateOutputCopyAtPath:outputFile.path fromPath:outputPath];
                
                playableProgress = self->_progress;
                [self dispatchVideoPartCanBePlayed:outputPath currentProgress:self->_progress delegate:delegate];
            }
            av_packet_unref(packet);
        }
        
        switch (operation.state) {
            case MuxingOperationStateSuccess:
            {
                [outputFile writeTrailer];
                [self renameFrom:outputFile.path to:outputPath];
                
                NSDate *endDate = [NSDate date];
                NSTimeInterval executionTime = [endDate timeIntervalSinceDate:startDate];
                NSLog(@"Done! frames = %d, execution = %f", counter, executionTime);
                
                [self dispatchMuxingFinished:outputPath size:readSizeBytes delegate:delegate];
            }
                break;
            case MuxingOperationStateCancelled:
                [self cancelConvertation:@[temporaryOutputPath, outputPath] delegate:delegate];
                break;
            default:
                break;
        }
        
        [self removeMuxingOperation:operation];
    });
}

- (void)createPreviewAnimationForVideo:(NSString *)inputPath
                                    at:(NSString *)outputPath
                            completion:(CompletionBlock)completion
{
    dispatch_queue_t convertQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul);
    dispatch_async(convertQueue, ^{
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:outputPath]) {
            [[NSFileManager defaultManager] removeItemAtPath:outputPath error:nil];
        }
        
        NSMutableArray<NSNumber *> *timePoints = [NSMutableArray arrayWithObjects:@(0.2f), @(0.5f), @(0.8f), nil];
        
        InputVideoFile *inputFile = [[InputVideoFile alloc] initWithPath:inputPath options:NULL];
        OutputVideoFile *outputFile = [[OutputVideoFile alloc] initWithPath:outputPath];
        
        NSDictionary *description = @{@"viewpoints_count": @(inputFile.streams.count), @"timepoints": timePoints};
        NSData *descriptionData = [NSJSONSerialization dataWithJSONObject:description options:0 error:nil];
        NSString *descriptionString = [[NSString alloc] initWithData:descriptionData encoding:NSUTF8StringEncoding];
        av_dict_set(&outputFile.formatContext->metadata, "description", [descriptionString UTF8String], 0);
        
        [outputFile createOutputStream:inputFile.firstStream->codecpar preferredIndex:0];
        BOOL success = [outputFile writeHeader];
        if (!success) {
            completion(NO);
            return;
        }
        
        int streamsCount = (int)inputFile.streams.count;
        NSMutableArray<VideoPacket *> *packets = [NSMutableArray new];
        NSMutableArray<VideoPacket *> *packetsRow = [NSMutableArray new];
        
        BOOL isReading = YES;
        AVPacket *packet = av_malloc(sizeof(AVPacket)); //av_packet_alloc();
        while (isReading)
        {
            isReading = [inputFile readIntoPacket:packet];
            if (!isReading) {
                break;
            }
            packet->pts = av_rescale_q(packet->pts, inputFile.streams[@(packet->stream_index)].stream->time_base, outputFile.firstStream->time_base);
            packet->dts = av_rescale_q(packet->dts, inputFile.streams[@(packet->stream_index)].stream->time_base, outputFile.firstStream->time_base);
            
            NSTimeInterval secs = (float)packet->pts / (outputFile.firstStream->time_base.den / outputFile.firstStream->time_base.num);
            if (secs >= [timePoints firstObject].doubleValue * inputFile.duration)
            {
                if ([packetsRow filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"streamId == %d", packet->stream_index]].count > 0) {
                    continue;
                }
                
                [packetsRow addObject:[[VideoPacket alloc] init:packet]];
                packet = av_malloc(sizeof(AVPacket));
                
                if (packetsRow.count == streamsCount) {
                    [packetsRow sortUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
                        VideoPacket *p_1 = (VideoPacket *)obj1;
                        VideoPacket *p_2 = (VideoPacket *)obj2;
                        return p_1.packet->stream_index > p_2.packet->stream_index;
                    }];
                    [packets addObjectsFromArray:packetsRow];
                    [packetsRow removeAllObjects];
                    
                    [timePoints removeObjectAtIndex:0];
                    if (timePoints.count == 0) {
                        break;
                    }
                }
            }
        }
        
        int64_t oneSecond = 1.0 * (outputFile.firstStream->time_base.den / outputFile.firstStream->time_base.num); //that's one second in pts value
        for (int i = 0; i < packets.count; i++) {
            AVPacket *packet = packets[i].packet;
            
            packet->stream_index = outputFile.firstStream->index;
            packet->dts = oneSecond * i;
            packet->pts = oneSecond * i;
            packet->duration = oneSecond;
            
            BOOL success = [outputFile writePacket:packet];
            if (!success) {
                NSLog(@"createPreviewAnimationForVideo: couldn't write a packet!");
                completion(NO);
                break;
            }
        }
        
        [outputFile writeTrailer];
        completion(YES);
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
    for(MuxingOperation *op in _operations) {
        op.state = MuxingOperationStateCancelled;
    }
}

- (void)notifyAboutAbortingOfConvertations:(id<VideoMuxerDelegate>)delegate
{
    [self dispatchMuxingDidCancelled:delegate];
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
