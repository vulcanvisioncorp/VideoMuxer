//
//  VideoStream.m
//  VULCAM
//
//  Created by Eugene Alexeev on 07/07/2017.
//  Copyright © 2017 Vulcan Vision Corporation. All rights reserved.
//

#import "VideoStream.h"

@implementation VideoStream

- (instancetype)initWithStream:(AVStream *)stream
{
    self = [super init];
    if (self) {
        
        _stream = stream;
    }
    
    return self;
}

- (AVStream *)stream
{
    return _stream;
}

- (void)dealloc
{
    
}

@end
