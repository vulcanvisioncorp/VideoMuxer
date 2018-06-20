//
//  VideoFile.m
//  VULCAM
//
//  Created by Eugene Alexeev on 03/07/2017.
//  Copyright © 2017 Vulcan Vision Corporation. All rights reserved.
//

#import "VideoFile.h"

#import <CoreGraphics/CoreGraphics.h>

@interface VideoFile()

@end

@implementation VideoFile

- (NSString *)path
{
    return _filePath;
}

- (instancetype)initWithPath:(NSString *)filePath
{
    self = [super init];
    if (self) {
        
        av_register_all();
        avcodec_register_all();
        avformat_network_init();
        
        _filePath = filePath;
        _streams = [NSMutableDictionary new];
    }
    
    return self;
}

- (void)clear
{
    if (_pFormatCtx) {
        avformat_free_context(_pFormatCtx);
    }
}

- (void)dealloc
{
    [self clear];
}
 
//test method
- (void)saveFrame:(AVFrame *)frame width:(int)img_width height:(int)img_height number:(int)number;
{
    CFDataRef data = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, frame->data[0], frame->linesize[0]*img_height, kCFAllocatorNull);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGImageRef cgImage = CGImageCreate(img_width, img_height,
                                       8, 24, frame->linesize[0],
                                       colorSpace, kCGBitmapByteOrderDefault,
                                       provider,
                                       NULL, NO, kCGRenderingIntentDefault);
    CGColorSpaceRelease(colorSpace);
    
    UIImage *image = [UIImage imageWithCGImage:cgImage];
    
    CGImageRelease(cgImage);
    CGDataProviderRelease(provider);
    CFRelease(data);
}

- (void)close {
    
    [self raiseExceptionWithMessage:@"This method should be overriden!"];
}

- (void)raiseExceptionWithMessage:(NSString *)msg
{
    [NSException raise:NSInternalInconsistencyException format:msg];
}

@end
