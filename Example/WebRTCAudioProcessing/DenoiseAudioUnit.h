//
//  DenoiseAudioUnit.h
//  WebRTCAudioProcessing_Example
//
//  Created by YJ on 2025/9/9.
//  Copyright © 2025 yjking10. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AudioProcessingWrapper.h"
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DenoiseAudioUnit : AVAudioUnit

// 可选：暴露参数控制（如降噪强度）
@property (nonatomic, assign) NoiseSuppressionLevel noiseSuppressionLevel;


@end

NS_ASSUME_NONNULL_END
