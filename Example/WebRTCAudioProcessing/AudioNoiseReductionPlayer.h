//
//  AudioNoiseReductionPlayer.h
//  WebRTCAudioProcessing_Example
//
//  Created by YJ on 2025/9/11.
//  Copyright © 2025 yjking10. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^AudioPlaybackCompletionHandler)(void);
typedef void (^AudioPlaybackErrorHandler)(NSError *error);

@interface AudioNoiseReductionPlayer : NSObject

@property (nonatomic, assign) BOOL isNoiseReductionEnabled;
@property (nonatomic, assign) float volume;
@property (nonatomic, assign, readonly) BOOL isPlaying;
@property (nonatomic, assign, readonly) NSTimeInterval currentTime;
@property (nonatomic, assign, readonly) NSTimeInterval duration;
@property (nonatomic, copy, nullable) AudioPlaybackCompletionHandler completionHandler;
@property (nonatomic, copy, nullable) AudioPlaybackErrorHandler errorHandler;

- (instancetype)initWithAudioFileURL:(NSURL *)fileURL;
- (void)play;
- (void)pause;
- (void)stop;
- (void)seekToTime:(NSTimeInterval)time;
- (void)seekToTime:(NSTimeInterval)time completion:(nullable void (^)(BOOL success))completion;

// 性能监控
- (CFTimeInterval)lastProcessingTime;
- (CFTimeInterval)maxProcessingTime;
- (void)resetPerformanceStats;

@end

NS_ASSUME_NONNULL_END
