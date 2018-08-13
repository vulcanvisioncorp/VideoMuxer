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
    
    _duration = (NSTimeInterval)_pFormatCtx->duration / (NSTimeInterval)AV_TIME_BASE;//_pFormatCtx->duration / (_firstStream->time_base.den / _firstStream->time_base.num);
    
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

- (AVFrame *)fetchFrameOutOfPacket:(AVPacket *)packet frameWidth:(int)width frameHeight:(int)height
{
    int64_t pts = packet->pts;
    int64_t dts = packet->dts;
    
    // Later I'll mix up two methods below
    int result = 0;
    result = avcodec_send_packet(_pCodecCtx, packet);
    if (result != 0) {
        NSLog(@"fetchFrameOutOfPacket: Couldn't send packet");
        return NULL;
    }
    
    AVFrame *originalFrame = av_frame_alloc();
    AVFrame *correctedFrame = av_frame_alloc();
    if (originalFrame == NULL || correctedFrame == NULL) {
        NSLog(@"fetchFrameOutOfPacket: Couldn't init frames!");
        return NULL;
    }

    result = avcodec_receive_frame(_pCodecCtx, originalFrame);
    av_packet_unref(packet);
    //originalFrame->pts = pts;
    //originalFrame->pkt_dts = dts;
    NSLog(@"pts = %lld", originalFrame->pts);
    
    
    return originalFrame;
    
    /*
    //prepare correctedFrame
    int numBytes = av_image_get_buffer_size(_pCodecCtx->pix_fmt, width, height, 32);
    uint8_t *buffer = (uint8_t *)av_malloc(numBytes * (sizeof(uint8_t)));
    av_image_fill_arrays(correctedFrame->data, correctedFrame->linesize,
                         buffer, _pCodecCtx->pix_fmt,
                         width, height, 32);
    correctedFrame->width = width;
    correctedFrame->height = height;
    correctedFrame->pict_type = originalFrame->pict_type;
    correctedFrame->pts = originalFrame->pts;
    correctedFrame->pkt_dts = originalFrame->pkt_dts;
    correctedFrame->format = originalFrame->format;
    //av_frame_set_color_range(correctedFrame, AVCOL_RANGE_JPEG);
    
    struct SwsContext *sws_ctx = sws_getContext(_pCodecCtx->width, _pCodecCtx->height, _pCodecCtx->pix_fmt,
                                                width, height, _pCodecCtx->pix_fmt,
                                                SWS_BILINEAR, NULL, NULL, NULL);
    
    sws_scale(sws_ctx, (uint8_t const * const *)originalFrame->data,
              originalFrame->linesize, 0, originalFrame->height,
              correctedFrame->data, correctedFrame->linesize);*/
    
    //av_frame_unref(originalFrame);
    //av_free(sws_ctx);
    
//    [self saveFrame:correctedFrame width:width height:height number:0];
    
 //   return originalFrame; //return correctedFrame;
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
