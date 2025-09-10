//
//  DenoiseAudioUnit.m
//  WebRTCAudioProcessing_Example
//
//  Created by YJ on 2025/9/9.
//  Copyright © 2025 yjking10. All rights reserved.
//

// DenoiseAudioUnit.m
#import "DenoiseAudioUnit.h"
//#import "DenoiseWrapper.h"  // 你的降噪类

//// 预声明
//static OSStatus DenoiseRenderProc(void *inRefCon,
//                                  AudioUnitRenderActionFlags *ioActionFlags,
//                                  const AudioTimeStamp *inTimeStamp,
//                                  UInt32 inBusNumber,
//                                  UInt32 inNumberFrames,
//                                  AudioBufferList *ioData);

@interface DenoiseAudioUnit ()
@property (nonatomic, strong, nullable) AudioProcessingWrapper *wrapper;
//@property (nonatomic, strong, nullable) AVAudioPCMBuffer *tempBuffer; // 用于临时包装 buffer
//@property (nonatomic, assign) NSUInteger lastFrameCount;
//@property (nonatomic, assign) NSUInteger channelCount;
//@end
@end

@implementation DenoiseAudioUnit

//- (instancetype)init {
//    if (!(self = [super init])) return nil;
//
//    _lastFrameCount = 0;
//    _channelCount = 0;
//
//    // 设置 render callback
//    AURenderCallbackStruct callback = {0};
//    callback.inputProc = DenoiseRenderProc;
//    callback.inputProcRefCon = (__bridge void *)self;
//    [self setRenderCallback:callback];
//
//    return self;
//}
//
//#pragma mark - Render Callback
//
//static OSStatus DenoiseRenderProc(void *inRefCon,
//                                  AudioUnitRenderActionFlags *ioActionFlags,
//                                  const AudioTimeStamp *inTimeStamp,
//                                  UInt32 inBusNumber,
//                                  UInt32 inNumberFrames,
//                                  AudioBufferList *ioData)
//{
//    DenoiseAudioUnit *unit = (__bridge DenoiseAudioUnit *)inRefCon;
//
//    // 更新通道数（首次）
//    if (unit.channelCount == 0) {
//        unit.channelCount = ioData->mNumberBuffers;
//    }
//
//    // 确保 inNumberFrames 是 10ms 对齐？（可选校验）
//    // 如果你的算法严格要求 10ms，这里可以 assert 或动态处理
//
//    // 直接对每个通道的 float 数据降噪
//    for (UInt32 i = 0; i < ioData->mNumberBuffers; i++) {
//        AudioBuffer buffer = ioData->mBuffers[i];
//        float *data = (float *)buffer.mData;
//        int frameCount = (int)(buffer.mDataByteSize / sizeof(float));
//
//        // 方法 1：如果你的 DenoiseWrapper 支持直接处理 float 数组
//        // [unit.wrapper processChannel:data length:frameCount channelIndex:i];
//
//        // 方法 2：如果必须用 AVAudioPCMBuffer，则复用 tempBuffer
//        if (!unit.tempBuffer || unit.lastFrameCount < frameCount) {
////            AVAudioFormat *fmt = [AVAudioFormat
////                                  formatWithCommonFormat:AVAudioPCMFormatFloat32
////                                  sampleRate:unit.outputFormatForBus[0].sampleRate
////                                  channels:1
////                                  interleaved:NO];
////            unit.tempBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:fmt
////                                                          frameCapacity:frameCount];
//            unit.lastFrameCount = frameCount;
//        }
//
//        unit.tempBuffer.frameLength = frameCount;
//        memcpy(unit.tempBuffer.floatChannelData[0], data, frameCount * sizeof(float));
//
//        // 执行降噪
//        [unit.wrapper processBuffer:unit.tempBuffer];
//
//        // 写回
//        memcpy(data, unit.tempBuffer.floatChannelData[0], frameCount * sizeof(float));
//    }
//
//    return noErr;
//}

#pragma mark - Format Handling

// AVAudioUnitEffect 要求实现 outputFormatForBus:
- (AVAudioFormat *)outputFormatForBus:(NSUInteger)bus {
    // 通常与输入格式一致
    return [super outputFormatForBus:bus];
}


#pragma mark - Parameters (Optional)




// 示例：暴露降噪强度参数
//- (NoiseSuppressionLevel)noiseSuppressionLevel {
//    // 假设 DenoiseWrapper 有 property
//    return [self.wrapper ];
//}

- (void)setNoiseSuppressionLevel:(NoiseSuppressionLevel)noiseSuppressionLevel {
    [self.wrapper setNoiseSuppressionLevel:noiseSuppressionLevel];

}


@end
