//
//  OutputVideoFile.m
//  VULCAM
//
//  Created by Eugene Alexeev on 05/07/2017.
//  Copyright © 2017 Vulcan Vision Corporation. All rights reserved.
//

#import "OutputVideoFile.h"

#include "opt.h"

@interface OutputVideoFile()
{
    
}

@end

@implementation OutputVideoFile

- (AVFormatContext *)formatContext
{
    return _pFormatCtx;
}

- (instancetype)initWithPath:(NSString *)filePath
{
    self = [super initWithPath:filePath];
    if (self) {
        
        _streams = [NSMutableDictionary new];
        
        [self initFormatContextForPath:filePath];
        [self createAndOpenFile];
    }
    
    return self;
}

- (void)initFormatContextForPath:(NSString *)outputPath
{
    int openOutputValue = avformat_alloc_output_context2(&_pFormatCtx, NULL, NULL, [outputPath UTF8String]);
    
    int list_size = 0;
    av_opt_set_int(_pFormatCtx->priv_data, "hls_list_size", list_size, 0);
    int hls_time = 3;
    av_opt_set_int(_pFormatCtx->priv_data, "hls_time", hls_time, 0);
    
    if (openOutputValue < 0) {
        
        avformat_free_context(_pFormatCtx);
        [self raiseExceptionWithMessage:@"Couldn't init format context for output file"];
    }
}

- (void)createOutputStreamsForFile:(InputVideoFile *)file
{
    NSArray *streamKeys = [file.streams.allKeys sortedArrayUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        return obj1 > obj2;
    }];
    
    for (NSNumber *streamId in streamKeys) {
        
        VideoStream *st = file.streams[streamId];
        [self createOutputStream:st.stream->codecpar preferredIndex:kVM_PreferredStreamId_Invalid];
    }
}

- (void)createOutputStream:(AVCodecParameters *)streamParams preferredIndex:(int)streamIndex
{
    AVCodec *codec = avcodec_find_encoder(streamParams->codec_id);
    if (!codec) {
        NSLog(@"codec not found: %@", codec);
        return;
    }
    
    AVStream *stream = avformat_new_stream(_pFormatCtx, codec);
    avcodec_parameters_copy(stream->codecpar, streamParams);
    stream->codecpar->codec_tag = 0;    //some silly workaround
    stream->index = streamIndex == kVM_PreferredStreamId_Invalid ? (int)_streams.count : streamIndex;
    
    if ([_streams objectForKey:@(stream->index)] != nil) {
        NSLog(@"OutputVideoFile: There's such stream id already!");
        return;
    }
    
    _streams[@(stream->index)] = [[VideoStream alloc] initWithStream:stream];
    if (_streams.count == 1) {
        _firstStream = stream;
    }
}

- (void)createAndOpenFile
{
    if (!(_pFormatCtx->oformat->flags & AVFMT_NOFILE)) {
        int ret = avio_open(&_pFormatCtx->pb, [_filePath UTF8String], AVIO_FLAG_WRITE);
        if (ret < 0)
        {
            [self raiseExceptionWithMessage:@"Couldn't open file for output"];
        }
    }
}

- (BOOL)writeHeader
{
    AVDictionary *options = NULL;
    int ret = avformat_write_header(_pFormatCtx, &options);
    
    BOOL success = YES;
    if (ret < 0) {
        success = NO;
    }
    
    av_dict_free(&options);
    return success;
}

- (BOOL)writePacket:(AVPacket *)packet
{
    int ret = av_interleaved_write_frame(_pFormatCtx, packet);
    if (ret == 0) {
        return YES;
    }

    return NO;
}

- (void)writeTrailer
{
    int ret = av_write_trailer(_pFormatCtx);
    if (ret < 0) {
        
        [self raiseExceptionWithMessage:@"Couldn't write trailer.."];
    }
}

@end
