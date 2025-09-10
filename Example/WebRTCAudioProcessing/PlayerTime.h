//
//  PlayerTime.h
//  WebRTCAudioProcessing_Example
//
//  Created by YJ on 2025/9/10.
//  Copyright © 2025 yjking10. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PlayerTime : NSObject
@property (nonatomic, assign) double elapsedTime;
@property (nonatomic, assign) double remainingTime;
+ (instancetype)zero;
@end

NS_ASSUME_NONNULL_END
