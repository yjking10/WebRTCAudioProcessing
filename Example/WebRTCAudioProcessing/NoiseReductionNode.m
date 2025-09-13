//
//  NoiseReductionNode.m
//  WebRTCAudioProcessing_Example
//
//  Created by YJ on 2025/9/11.
//  Copyright © 2025 yjking10. All rights reserved.
//

#import "NoiseReductionNode.h"

@interface NoiseReductionNode () {
    AudioBufferList _inputBuffer;
    AudioBufferList _outputBuffer;
    BOOL _buffersInitialized;
    dispatch_queue_t _processingQueue;
    dispatch_semaphore_t _bufferSemaphore;
    CFTimeInterval _lastProcessingTime;
    CFTimeInterval _maxProcessingTime;
    NSUInteger _processingCount;
    BOOL _needsFallback;
    NSMutableArray<AVAudioPCMBuffer *> *_bufferPool;
}

@property (nonatomic, strong) AVAudioUnit *audioUnit;
@property (nonatomic, strong) AVAudioFormat *processingFormat;
@property (nonatomic, assign) AUAudioFrameCount maximumFramesToRender;
@property (nonatomic, assign) BOOL shouldBypass;

@end

@implementation NoiseReductionNode

- (instancetype)initWithFormat:(AVAudioFormat *)format {
    self = [super init];
    if (self) {
        _processingFormat = format;
        _enabled = YES;
        _shouldBypass = NO;
        _needsFallback = NO;
        _buffersInitialized = NO;
        
        _processingQueue = dispatch_queue_create("com.audio.noisereduction.processing", DISPATCH_QUEUE_SERIAL);
        _bufferSemaphore = dispatch_semaphore_create(1);
        _bufferPool = [NSMutableArray array];
        
        // 创建WebRTC音频处理器
        _audioProcessor = [[AudioProcessingWrapper alloc] init];
//        [_audioProcessor setSampleRate:format.sampleRate];
//        [_audioProcessor setStreamDelay:0];
//        
        // 配置最优缓冲区大小
        [self configureOptimalBufferSize];
        
        // 创建音频单元
        [self createAudioUnit];
    }
    return self;
}

- (void)createAudioUnit {
    AudioComponentDescription componentDesc = {
        .componentType = kAudioUnitType_Effect,
        .componentSubType = 'nrsp',
        .componentManufacturer = 'appl',
        .componentFlags = 0,
        .componentFlagsMask = 0
    };
    
    __weak typeof(self) weakSelf = self;
    AVAudioUnitInstantiationBlock instantiationBlock = ^(AVAudioUnit *audioUnit, NSError **outError) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        
        // 设置渲染回调
        AudioUnitAddRenderNotify(audioUnit.audioUnit, renderNotification, (__bridge void *)strongSelf);
        
        return YES;
    };
    
    _audioUnit = [[AVAudioUnit alloc] initWithComponentDescription:componentDesc
                                                          options:0
                                               instantiationBlock:instantiationBlock];
    
    [self attachNode:_audioUnit];
}

- (void)configureOptimalBufferSize {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSTimeInterval ioBufferDuration = 0.0;
    
    @try {
        ioBufferDuration = audioSession.IOBufferDuration;
    } @catch (NSException *exception) {
        ioBufferDuration = 0.005; // 默认5ms
    }
    
    // 计算最优帧数
    NSUInteger optimalFrameCount = _processingFormat.sampleRate * ioBufferDuration;
    
    // 确保是WebRTC需要的10ms的倍数
    NSUInteger webrtcFrameSize = _processingFormat.sampleRate * 0.01;
    optimalFrameCount = ((optimalFrameCount + webrtcFrameSize - 1) / webrtcFrameSize) * webrtcFrameSize;
    
    // 限制最小和最大帧数
    optimalFrameCount = MAX(webrtcFrameSize, MIN(optimalFrameCount, webrtcFrameSize * 4));
    
    _maximumFramesToRender = (AUAudioFrameCount)optimalFrameCount;
    
    NSLog(@"NoiseReductionNode: Optimal buffer size: %lu frames (%.2f ms)",
          (unsigned long)optimalFrameCount,
          optimalFrameCount / _processingFormat.sampleRate * 1000);
}

- (void)initializeBuffersForFrameCount:(UInt32)frameCount {
    if (_buffersInitialized) return;
    
    UInt32 channels = _processingFormat.channelCount;
    UInt32 bufferSize = frameCount * sizeof(float);
    
    // 初始化输入缓冲区
    _inputBuffer.mNumberBuffers = channels;
    for (UInt32 i = 0; i < channels; i++) {
        _inputBuffer.mBuffers[i].mNumberChannels = 1;
        _inputBuffer.mBuffers[i].mDataByteSize = bufferSize;
        _inputBuffer.mBuffers[i].mData = malloc(bufferSize);
    }
    
    // 初始化输出缓冲区
    _outputBuffer.mNumberBuffers = channels;
    for (UInt32 i = 0; i < channels; i++) {
        _outputBuffer.mBuffers[i].mNumberChannels = 1;
        _outputBuffer.mBuffers[i].mDataByteSize = bufferSize;
        _outputBuffer.mBuffers[i].mData = malloc(bufferSize);
    }
    
    _buffersInitialized = YES;
}

- (AVAudioPCMBuffer *)getBufferFromPoolWithFrameCount:(UInt32)frameCount {
    @synchronized (_bufferPool) {
        for (AVAudioPCMBuffer *buffer in _bufferPool) {
            if (buffer.frameCapacity >= frameCount) {
                [_bufferPool removeObject:buffer];
                buffer.frameLength = frameCount;
                return buffer;
            }
        }
    }
    
    AVAudioPCMBuffer *newBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:_processingFormat
                                                               frameCapacity:frameCount];
    newBuffer.frameLength = frameCount;
    return newBuffer;
}

- (void)returnBufferToPool:(AVAudioPCMBuffer *)buffer {
    @synchronized (_bufferPool) {
        if (_bufferPool.count < 8) { // 限制池大小
            [_bufferPool addObject:buffer];
        }
    }
}

static OSStatus renderNotification(void *inRefCon,
                                  AudioUnitRenderActionFlags *ioActionFlags,
                                  const AudioTimeStamp *inTimeStamp,
                                  UInt32 inBusNumber,
                                  UInt32 inNumberFrames,
                                  AudioBufferList *ioData) {
    NoiseReductionNode *self = (__bridge NoiseReductionNode *)inRefCon;
    
    if (*ioActionFlags & kAudioUnitRenderAction_PreRender) {
        if (self.enabled && !self.shouldBypass) {
            // 初始化缓冲区（如果需要）
            [self initializeBuffersForFrameCount:inNumberFrames];
            
            // 复制输入数据
            for (UInt32 i = 0; i < ioData->mNumberBuffers && i < self->_inputBuffer.mNumberBuffers; i++) {
                if (ioData->mBuffers[i].mData && self->_inputBuffer.mBuffers[i].mData) {
                    memcpy(self->_inputBuffer.mBuffers[i].mData,
                          ioData->mBuffers[i].mData,
                          ioData->mBuffers[i].mDataByteSize);
                }
            }
        }
    }
    
    if (*ioActionFlags & kAudioUnitRenderAction_PostRender) {
        if (self.enabled && !self.shouldBypass) {
            CFTimeInterval startTime = CACurrentMediaTime();
            
            // 处理音频数据
            [self processAudioBuffers:ioData frameCount:inNumberFrames];
            
            // 更新性能统计
            CFTimeInterval processingTime = CACurrentMediaTime() - startTime;
            self->_lastProcessingTime = processingTime;
            self->_maxProcessingTime = MAX(self->_maxProcessingTime, processingTime);
            self->_processingCount++;
            
            // 检查是否需要降级
            NSTimeInterval frameDuration = inNumberFrames / self.processingFormat.sampleRate;
            if (processingTime > frameDuration * 0.7) {
                self->_needsFallback = YES;
                NSLog(@"NoiseReductionNode: Processing too slow, enabling fallback");
            }
        }
    }
    
    return noErr;
}

- (void)processAudioBuffers:(AudioBufferList *)ioData frameCount:(UInt32)frameCount {
    if (!_audioProcessor || frameCount == 0 || _needsFallback) {
        return;
    }
    
    @autoreleasepool {
        AVAudioPCMBuffer *buffer = [self getBufferFromPoolWithFrameCount:frameCount];
        
        // 设置缓冲区数据指针（零拷贝）
        for (UInt32 i = 0; i < ioData->mNumberBuffers && i < buffer.format.channelCount; i++) {
            buffer.floatChannelData[i] = ioData->mBuffers[i].mData;
        }
        
        // 处理音频
        [_audioProcessor processBuffer:buffer];
        
        // 数据已经在原位置被修改，不需要拷贝回去
        [self returnBufferToPool:buffer];
        
        // 定期清理和报告
        if (_processingCount % 500 == 0) {
            [self updateProcessingStats];
        }
    }
}

- (void)updateProcessingStats {
    NSLog(@"NoiseReductionNode: Processing stats - last: %.3fms, max: %.3fms, fallback: %@",
          _lastProcessingTime * 1000,
          _maxProcessingTime * 1000,
          _needsFallback ? @"YES" : @"NO");
    
    _maxProcessingTime = 0;
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.shouldBypass = !enabled;
        
        if (enabled) {
            strongSelf->_needsFallback = NO; // 重置降级状态
        }
    });
}

- (void)dealloc {
    // 释放缓冲区内存
    if (_buffersInitialized) {
        for (UInt32 i = 0; i < _inputBuffer.mNumberBuffers; i++) {
            if (_inputBuffer.mBuffers[i].mData) {
                free(_inputBuffer.mBuffers[i].mData);
            }
        }
        for (UInt32 i = 0; i < _outputBuffer.mNumberBuffers; i++) {
            if (_outputBuffer.mBuffers[i].mData) {
                free(_outputBuffer.mBuffers[i].mData);
            }
        }
    }
    
    // 清空内存池
    @synchronized (_bufferPool) {
        [_bufferPool removeAllObjects];
    }
}

@end
