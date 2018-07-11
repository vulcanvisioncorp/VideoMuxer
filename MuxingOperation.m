//
//  MuxingOperation.m
//  VULCAM
//
//  Created by Eugene Alexeev on 10/07/2018.
//  Copyright © 2018 Vulcan Vision Corporation. All rights reserved.
//

#import "MuxingOperation.h"

@implementation MuxingOperation

- (instancetype)init:(MuxingOperationState)state fileName:(NSString *)name
{
    self = [super init];
    if (self) {
        _state = state;
        _fileName = name;
    }
    
    return self;
}

@end
