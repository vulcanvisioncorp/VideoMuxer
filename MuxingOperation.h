//
//  MuxingOperation.h
//  VULCAM
//
//  Created by Eugene Alexeev on 10/07/2018.
//  Copyright © 2018 Vulcan Vision Corporation. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MuxingOperationState) {
    MuxingOperationStateReading = 0,
    MuxingOperationStateSuccess = 1,
    MuxingOperationStateCancelled = 2
};

@interface MuxingOperation : NSObject

@property (nonatomic) MuxingOperationState state;
@property (nonatomic, readonly) NSString *fileName;

- (instancetype)init:(MuxingOperationState)state fileName:(NSString *)name;

@end
