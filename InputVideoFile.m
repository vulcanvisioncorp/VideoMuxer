//
//  InputVideoFile.m
//  VULCAM
//
//  Created by Eugene Alexeev on 05/07/2017.
//  Copyright © 2017 Vulcan Vision Corporation. All rights reserved.
//

#import "InputVideoFile.h"

@interface InputVideoFile()
{
    AVCodecParameters *_pCodecParams;
    AVCodecContext *_pCodecCtx;
    AVCodec *_pCodec;
}

@end

@implementation InputVideoFile

- (AVCodec *)codec
{
    return _pCodec;
}

- (AVCodecParameters *)codecParams
{
    return _pCodecParams;
}

- (instancetype)initWithPath:(NSString *)filePath options:(AVDictionary *)options
{
    self = [super initWithPath:filePath];
    if (self && [self openFile:filePath options:options]) {
        
        return self;
    }
    
    return nil;
}

- (BOOL)openFile:(NSString *)filePath options:(AVDictionary *)options
{
    _pFormatCtx = NULL;

    if (avformat_open_input(&_pFormatCtx, [filePath UTF8String], NULL, &options) != 0) {
        //[self raiseExceptionWithMessage:@"Couldn't open the file!"];
        return NO;
    }
    
    if (avformat_find_stream_info(_pFormatCtx, NULL) < 0) {
        //[self raiseExceptionWithMessage:@"Couldn't find stream info!"];
        return NO;
    }
    
   // _videoStream = -1;
    int stream_index = 0;
    for (int i = 0; i < _pFormatCtx->nb_streams; i++)
    {
        AVStream *st = _pFormatCtx->streams[i];
        if (_pFormatCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO)
        {
            st->index = stream_index;
            _streams[@(st->index)] = [[VideoStream alloc] initWithStream:st];
            stream_index++;
        }
    }
    
    _firstStream = [_streams.allValues firstObject].stream;
    
    if (_streams.count == 0) {
        //[self raiseExceptionWithMessage:@"Couldn't find videostream!"];
        return NO;
    }
    
    _pCodecParams = [self firstStream]->codecpar;
    _pCodec = avcodec_find_decoder(_pCodecParams->codec_id);
    
    if (!_pCodec) {
//        [self raiseExceptionWithMessage:@"Unsupported codec!"];
        return NO;
    }
    
    _pCodecCtx = avcodec_alloc_context3(_pCodec);
    if (avcodec_parameters_to_context(_pCodecCtx, _pCodecParams) < 0) {
        //[self raiseExceptionWithMessage:@"Couldn't copy params into codec"];
        return NO;
    }
    
    if (avcodec_open2(_pCodecCtx, _pCodec, 0) < 0) {
        //[self raiseExceptionWithMessage:@"Couldn't open the Codec!"];
        return NO;
    }
    
    return YES;
}

- (BOOL)readIntoPacket:(AVPacket *)packet
{
    if (av_read_frame(_pFormatCtx, packet) == 0) {
        return YES;
    }
    
    return NO;
}

- (BOOL)readIntoPacketFromFirstStream:(AVPacket *)packet
{
    BOOL success = NO;
    while (av_read_frame(_pFormatCtx, packet) == 0) {
        if (packet->stream_index == _firstStream->index) {
            success = YES;
            break;
        }
    }
    
    return success;
}
- (void)clear
{
    avformat_close_input(&_pFormatCtx);
    if (_pFormatCtx) {
        avformat_free_context(_pFormatCtx);
    }
    
    if (_pCodecCtx) {
        avcodec_free_context(&_pCodecCtx);
    }
}

@end
