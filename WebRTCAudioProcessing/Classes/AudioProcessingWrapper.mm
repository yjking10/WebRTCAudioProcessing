#import "AudioProcessingWrapper.h"
#import <Foundation/Foundation.h>

// WebRTC C++ headers
#include "webrtc-audio-processing-2/modules/audio_processing/include/audio_processing.h"

using namespace webrtc;

@implementation AudioProcessingWrapper {
    scoped_refptr<AudioProcessing> _apm;
    NSMutableData *_processedBuffer;
    AudioProcessing::Config _currentConfig;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self resetToDefaultConfiguration];
        _processedBuffer = [NSMutableData data];
    }
    return self;
}

- (void)resetToDefaultConfiguration {
    AudioProcessing::Config config;

    // Default noise suppression (can be adjusted later)
    config.noise_suppression.enabled = true;
    config.noise_suppression.level = AudioProcessing::Config::NoiseSuppression::kHigh;

    // Default gain control
    config.gain_controller1.enabled = true;
    config.gain_controller1.mode = AudioProcessing::Config::GainController1::kAdaptiveDigital;
    config.gain_controller1.target_level_dbfs = 3;
    config.gain_controller1.compression_gain_db = 12;
    config.gain_controller1.enable_limiter = true;

    // Default high-pass filter
    config.high_pass_filter.enabled = true;

    // Default echo cancellation (off by default for pure recording)
    config.echo_canceller.enabled = false;

    // Default transient suppression
    config.transient_suppression.enabled = true;

    _currentConfig = config;
    [self applyCurrentConfiguration];
}

- (void)applyCurrentConfiguration {
    if (!_apm) {
        _apm = AudioProcessingBuilder().Create();
    }
    _apm->ApplyConfig(_currentConfig);
    _apm->Initialize();
}

#pragma mark - Dynamic Configuration Methods

- (void)setNoiseSuppressionLevel:(NoiseSuppressionLevel)level {
    switch (level) {
        case NoiseSuppressionLevelLow:
            _currentConfig.noise_suppression.level = AudioProcessing::Config::NoiseSuppression::kLow;
            break;
        case NoiseSuppressionLevelModerate:
            _currentConfig.noise_suppression.level = AudioProcessing::Config::NoiseSuppression::kModerate;
            break;
        case NoiseSuppressionLevelHigh:
            _currentConfig.noise_suppression.level = AudioProcessing::Config::NoiseSuppression::kHigh;
            break;
        case NoiseSuppressionLevelVeryHigh:
            _currentConfig.noise_suppression.level = AudioProcessing::Config::NoiseSuppression::kVeryHigh;
            break;
    }
    [self applyCurrentConfiguration];
}

- (void)setNoiseSuppressionEnabled:(BOOL)enabled {
    _currentConfig.noise_suppression.enabled = enabled;
    [self applyCurrentConfiguration];
}

- (void)setGainControllerMode:(GainControllerMode)mode {
    switch (mode) {
        case GainControllerModeAdaptiveAnalog:
            _currentConfig.gain_controller1.mode = AudioProcessing::Config::GainController1::kAdaptiveAnalog;
            break;
        case GainControllerModeAdaptiveDigital:
            _currentConfig.gain_controller1.mode = AudioProcessing::Config::GainController1::kAdaptiveDigital;
            break;
        case GainControllerModeFixedDigital:
            _currentConfig.gain_controller1.mode = AudioProcessing::Config::GainController1::kFixedDigital;
            break;
    }
    [self applyCurrentConfiguration];
}

- (void)setTargetLevelDbfs:(int)level {
    _currentConfig.gain_controller1.target_level_dbfs = level;
    [self applyCurrentConfiguration];
}

- (void)setCompressionGainDb:(int)gain {
    _currentConfig.gain_controller1.compression_gain_db = gain;
    [self applyCurrentConfiguration];
}

- (void)setHighPassFilterEnabled:(BOOL)enabled {
    _currentConfig.high_pass_filter.enabled = enabled;
    [self applyCurrentConfiguration];
}

- (void)setEchoCancellationEnabled:(BOOL)enabled {
    _currentConfig.echo_canceller.enabled = enabled;
    [self applyCurrentConfiguration];
}

- (void)setTransientSuppressionEnabled:(BOOL)enabled {
    _currentConfig.transient_suppression.enabled = enabled;
    [self applyCurrentConfiguration];
}

#pragma mark - Audio Processing

- (NSData *)processAudioFrame:(NSData *)pcmData sampleRate:(int)sampleRate channels:(int)channels {
    if (!pcmData || pcmData.length == 0) return nil;
    if (sampleRate <= 0 || channels <= 0) return nil;

    const int16_t *audioFrame = (const int16_t *)pcmData.bytes;

    // Reuse buffer
    _processedBuffer.length = pcmData.length;
    int16_t *processedFrame = (int16_t *)_processedBuffer.mutableBytes;

    webrtc::StreamConfig config(sampleRate, channels);
    int result = _apm->ProcessStream(audioFrame, config, config, processedFrame);

    if (result != webrtc::AudioProcessing::kNoError) {
        NSLog(@"Audio processing failed: %d", result);
        return nil;
    }

    return [_processedBuffer copy];
}


- (NSData *)processAudioFrameFloat:(NSData *)pcmData sampleRate:(int)sampleRate channels:(int)channels {
    if (!pcmData || pcmData.length == 0) return nil;
    if (sampleRate <= 0 || channels <= 0) return nil;

    const float *interleaved = (const float *)pcmData.bytes;
    int frameCount = (int)(pcmData.length / sizeof(float) / channels);

    // Step 1: 分配 deinterleaved buffers（src 和 dest）
    float **srcChannels = (float **)calloc(channels, sizeof(float*));
    float **destChannels = (float **)calloc(channels, sizeof(float*));

    // 为每个 channel 分配 buffer
    for (int c = 0; c < channels; c++) {
        srcChannels[c] = (float *)malloc(frameCount * sizeof(float));
        destChannels[c] = (float *)malloc(frameCount * sizeof(float));
    }

    // Step 2: Interleaved → Deinterleaved
    for (int c = 0; c < channels; c++) {
        for (int i = 0; i < frameCount; i++) {
            srcChannels[c][i] = interleaved[i * channels + c];
        }
    }

    // Step 3: WebRTC 处理（降噪、AGC、AEC 等）
    webrtc::StreamConfig config(sampleRate, channels); // float = true

    int result = _apm->ProcessStream(
        const_cast<const float* const*>(srcChannels),  // src
        config,                                        // input config
        config,                                        // output config
        destChannels                                   // dest
    );

    if (result != webrtc::AudioProcessing::kNoError) {
        NSLog(@"Audio processing failed: %d", result);

        // 清理
        for (int c = 0; c < channels; c++) {
            free(srcChannels[c]);
            free(destChannels[c]);
        }
        free(srcChannels);
        free(destChannels);

        return nil;
    }

    // Step 4: Deinterleaved → Interleaved（写回）
    NSMutableData *outputData = [[NSMutableData alloc] initWithLength:frameCount * channels * sizeof(float)];
    float *outInterleaved = (float *)outputData.mutableBytes;

    for (int i = 0; i < frameCount; i++) {
        for (int c = 0; c < channels; c++) {
            outInterleaved[i * channels + c] = destChannels[c][i];
        }
    }

    // Step 5: 清理
    for (int c = 0; c < channels; c++) {
        free(srcChannels[c]);
        free(destChannels[c]);
    }
    free(srcChannels);
    free(destChannels);

    return [outputData copy];
}

@end
