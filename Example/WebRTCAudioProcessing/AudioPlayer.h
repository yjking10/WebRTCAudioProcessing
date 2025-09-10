//
//  AudioPlayer.h
//  WebRTCAudioProcessing_Example
//
//  Created by YJ on 2025/9/10.
//  Copyright © 2025 yjking10. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
NS_ASSUME_NONNULL_BEGIN


// 音频播放器类
@interface AudioPlayer : NSObject
@property (nonatomic, assign, readonly) BOOL isPlaying;
@property (nonatomic, assign) BOOL noiseSuppressionEnabled;

- (void)playLocalAudio:(NSURL *)fileURL;
- (void)playRemoteAudio:(NSURL *)url;
- (void)play;
- (void)pause;
- (void)stop;
@end


NS_ASSUME_NONNULL_END
