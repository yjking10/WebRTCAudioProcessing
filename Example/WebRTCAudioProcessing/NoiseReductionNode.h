#import <AVFoundation/AVFoundation.h>
#import "AudioProcessingWrapper.h"

NS_ASSUME_NONNULL_BEGIN

@interface NoiseReductionNode : AVAudioNode

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, strong, readonly) AudioProcessingWrapper *audioProcessor;
@property (nonatomic, assign, readonly) CFTimeInterval lastProcessingTime;
@property (nonatomic, assign, readonly) CFTimeInterval maxProcessingTime;

- (instancetype)initWithFormat:(AVAudioFormat *)format;
- (void)updateProcessingStats;

@end

NS_ASSUME_NONNULL_END
