//
//  NoiseReducedPlayer.h
//  WebRTCAudioProcessing_Example
//
//  Created by YJ on 2025/9/9.
//  Copyright © 2025 yjking10. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PlayerTime.h"
#import "PlaybackValue.h"

NS_ASSUME_NONNULL_BEGIN

@interface NoiseReducedPlayer : NSObject

@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, assign) BOOL isPlayerReady;
@property (nonatomic, assign) double playerProgress;
@property (nonatomic, strong) PlayerTime *playerTime;
@property (nonatomic, assign) float meterLevel;

- (void)playFile0:(NSURL *)url ;

- (void)playFile:(NSURL *)url;
@end

NS_ASSUME_NONNULL_END
