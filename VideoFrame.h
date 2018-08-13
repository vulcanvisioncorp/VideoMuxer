//
//  VideoFrame.h
//  VULCAM
//
//  Created by Eugene Alexeev on 13/08/2018.
//  Copyright © 2018 Vulcan Vision Corporation. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "avcodec.h"

@interface VideoFrame : NSObject

- (instancetype)init:(AVFrame *)frame;

@property(nonatomic, readonly) AVFrame *frame;

@end
