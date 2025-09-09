#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, NoiseSuppressionLevel) {
    NoiseSuppressionLevelLow,
            NoiseSuppressionLevelModerate,
            NoiseSuppressionLevelHigh,
            NoiseSuppressionLevelVeryHigh
};

typedef NS_ENUM(NSUInteger, GainControllerMode) {
GainControllerModeAdaptiveAnalog,
GainControllerModeAdaptiveDigital,
GainControllerModeFixedDigital
};

@interface AudioProcessingWrapper : NSObject

- (instancetype)init;

// Reset to default configuration
- (void)resetToDefaultConfiguration;

// Noise suppression configuration
- (void)setNoiseSuppressionLevel:(NoiseSuppressionLevel)level;
- (void)setNoiseSuppressionEnabled:(BOOL)enabled;

// Gain controller configuration
- (void)setGainControllerMode:(GainControllerMode)mode;
- (void)setTargetLevelDbfs:(int)level;
- (void)setCompressionGainDb:(int)gain;

// Filter configuration
- (void)setHighPassFilterEnabled:(BOOL)enabled;

// Echo cancellation
- (void)setEchoCancellationEnabled:(BOOL)enabled;

// Transient suppression
- (void)setTransientSuppressionEnabled:(BOOL)enabled;

// Audio processing
- (NSData *)processAudioFrame:(NSData *)pcmData sampleRate:(int)sampleRate channels:(int)channels;


- (NSData *)processAudioFrameFloat:(NSData *)pcmData sampleRate:(int)sampleRate channels:(int)channels ;
@end

NS_ASSUME_NONNULL_END
