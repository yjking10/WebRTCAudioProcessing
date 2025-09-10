//
//  PlaybackValue.h
//  WebRTCAudioProcessing_Example
//
//  Created by YJ on 2025/9/10.
//  Copyright © 2025 yjking10. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


@interface PlaybackValue : NSObject

@property (nonatomic, assign) double value;
@property (nonatomic, copy) NSString *label;

- (instancetype)initWithValue:(double)value label:(NSString *)label;

@end

NS_ASSUME_NONNULL_END
