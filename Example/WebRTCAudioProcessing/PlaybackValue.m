//
//  PlaybackValue.m
//  WebRTCAudioProcessing_Example
//
//  Created by YJ on 2025/9/10.
//  Copyright © 2025 yjking10. All rights reserved.
//

#import "PlaybackValue.h"
#pragma mark - PlaybackValue Implementation

@implementation PlaybackValue

- (instancetype)initWithValue:(double)value label:(NSString *)label {
    self = [super init];
    if (self) {
        _value = value;
        _label = label;
    }
    return self;
}

@end
