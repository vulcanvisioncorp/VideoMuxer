//
//  VideoStream.h
//  VULCAM
//
//  Created by Eugene Alexeev on 07/07/2017.
//  Copyright © 2017 Vulcan Vision Corporation. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "avformat.h"

@interface VideoStream : NSObject
{
    AVStream *_stream;
}

- (instancetype)initWithStream:(AVStream *)stream;

@property (nonatomic, readonly) AVStream *stream;

@end
