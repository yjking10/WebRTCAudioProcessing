//
//  PlayerViewModel2.h
//  WebRTCAudioProcessing_Example
//
//  Created by YJ on 2025/9/10.
//  Copyright © 2025 yjking10. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "PlaybackValue.h"



#import <AVFoundation/AVFoundation.h>
#import "PlayerTime.h"

NS_ASSUME_NONNULL_BEGIN



@interface YJAudioPlayer : NSObject

@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, assign) BOOL isPlayerReady;

@property (nonatomic, assign) double playerProgress;
@property (nonatomic, strong) PlayerTime *playerTime;
@property (nonatomic, assign) float meterLevel;

- (void)setupAudioPath:(NSString *)filePath ;

- (void)setupAudioUrl:(NSURL  *)url ;


- (void)playOrPause;
- (void)skipForwards:(BOOL)forwards;

@end



NS_ASSUME_NONNULL_END
