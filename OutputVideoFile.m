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
    AVCodecContext *_pCodecCtx;
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

- (void)initCodecContextIfNeeded:(AVCodecParameters *)params
{
    AVCodec *pCodec = avcodec_find_encoder(params->codec_id);
    if (!pCodec) {
        NSLog(@"initContextIfNeeded: couldn't create codec!");
        return;
    }
    
    _pCodecCtx = avcodec_alloc_context3(pCodec);
    if (avcodec_parameters_to_context(_pCodecCtx, params) < 0) {
        NSLog(@"initContextIfNeeded: couldn't copy params to codec context!");
        return;
    }
    
    _pCodecCtx->time_base = (AVRational){1, 30}; //hard cooode...
    
    if (avcodec_open2(_pCodecCtx, pCodec, 0) < 0) {
        NSLog(@"initContextIfNeeded: Couldn't open codec!");
        return;
    }
}

- (void)createOutputStreamsForFile:(InputVideoFile *)file
{
    NSArray *streamKeys = [file.streams.allKeys sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        
        if ([obj1 intValue] == [obj2 intValue])
            return NSOrderedSame;
        
        else if ([obj1 intValue] < [obj2 intValue])
            return NSOrderedAscending;
        
        else
            return NSOrderedDescending;
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
        
        //AVCodecParameters *pCodecParams = _firstStream->codecpar;
        //[self initCodecContextIfNeeded:pCodecParams];
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

- (BOOL)writeFrame:(AVFrame *)frame streamIndex:(int)stream_index
{
    int64_t pts = frame->pts;
    int64_t dts = frame->pkt_dts;
    int result = avcodec_send_frame(_pCodecCtx, frame);
    if (result != 0) {
        NSLog(@"fetchFrameOutOfPacket: Couldn't send corrected frame");
        av_frame_unref(frame);
        return NO; //test
    }
    
    AVPacket *pkt = av_packet_alloc(); //nil; //av_malloc(sizeof(AVPacket));
    
    while (result >= 0) {
        result = avcodec_receive_packet(_pCodecCtx, pkt);
        if (result == 0) {
            pkt->stream_index = stream_index;
            pkt->pts = pts;
            pkt->dts = dts;
            NSLog(@"That's a success, bitches! = %d, pts = %lld, dts = %lld, stream_index = %d", pkt->size, pkt->pts, pkt->dts, pkt->stream_index);
            if (![self writePacket:pkt]) {
                return NO;
            }
        } else if (result == AVERROR(EOF)) {
            av_frame_unref(frame);
            return NO;
        }
    }
    av_frame_unref(frame);
    
    return YES;//[self writePacket:pkt];
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
