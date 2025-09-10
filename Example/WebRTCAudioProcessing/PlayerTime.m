//
//  PlayerTime.m
//  WebRTCAudioProcessing_Example
//
//  Created by YJ on 2025/9/10.
//  Copyright © 2025 yjking10. All rights reserved.
//

#import "PlayerTime.h"

@implementation PlayerTime
+ (instancetype)zero {
    PlayerTime *t = [[PlayerTime alloc] init];
    t.elapsedTime = 0;
    t.remainingTime = 0;
    return t;
}
@end
