//
//  VideoFrame.m
//  VULCAM
//
//  Created by Eugene Alexeev on 13/08/2018.
//  Copyright © 2018 Vulcan Vision Corporation. All rights reserved.
//

#import "VideoFrame.h"

@implementation VideoFrame

- (instancetype)init:(AVFrame *)frame
{
    self = [super init];
    if (self) {
        _frame = frame;
    }
    
    return self;
}

@end
