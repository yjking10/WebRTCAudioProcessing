// AudioPlayerFlauto.m
#import "AudioPlayerFlauto.h"
#import <WebRTCAudioProcessing/AudioProcessingWrapper.h>
#import <AVFoundation/AVFoundation.h>

@class FlautoPlayer;

@interface AudioPlayerFlauto ()
//<AVAudioPlayerNodeCompletionCallback>
@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) AVAudioPlayerNode *playerNode;
@property (nonatomic, strong) AVAudioFile *audioFile;
@property (nonatomic, strong) NSURL *sourceURL;
@property (nonatomic, strong) AudioProcessingWrapper *audioProcessor;

@property (nonatomic, assign) double m_sampleRate;
@property (nonatomic, assign) int m_numChannels;
@property (nonatomic, assign) BOOL isStreaming;

// 状态管理
@property (nonatomic, strong) dispatch_queue_t stateQueue;
@property (nonatomic, strong) dispatch_queue_t processingQueue;
@property (nonatomic, strong) CADisplayLink *positionTimer;

// 缓存
@property (nonatomic, strong) NSURL *cachedFileURL;
@end

@implementation AudioPlayerFlauto {
    FlautoPlayer* flautoPlayer; // Owner
}

- (instancetype)init:(FlautoPlayer*)owner {
    if (self = [super init]) {
        flautoPlayer = owner;

        self.stateQueue = dispatch_queue_create("audio.player.state", DISPATCH_QUEUE_SERIAL);
        self.processingQueue = dispatch_queue_create("audio.processing", DISPATCH_QUEUE_SERIAL);

        self.engine = [[AVAudioEngine alloc] init];
        self.playerNode = [[AVAudioPlayerNode alloc] init];
        self.audioProcessor = [[AudioProcessingWrapper alloc] init];

        [self setupAudioSession];
        [self setupEngine];
    }
    return self;
}

#pragma mark - Engine Setup

- (void)setupAudioSession {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;
    [session setCategory:AVAudioSessionCategoryPlayback
                 withOptions:AVAudioSessionCategoryOptionAllowBluetooth error:&error];
    if (error) NSLog(@"setCategory error: %@", error);
    [session setActive:YES error:&error];
    if (error) NSLog(@"setActive error: %@", error);
}

- (void)setupEngine {
    [self.engine attachNode:self.playerNode];
//    AVAudioFormat *mainFormat = [self.engine outputNode].inputFormatForBus:0];
    
    // 使用源文件格式作为主混音格式
    AVAudioOutputNode *outputNode = [self.engine outputNode];
    if (!outputNode) {
        NSLog(@"错误：无法获取输出节点");
        return;
    }

    AVAudioMixerNode *mainMixer = [self.engine mainMixerNode];
    if (!mainMixer) {
        NSLog(@"错误：无法获取主混音器节点");
        return;
    }

    // 从主混音器获取输出格式通常比从outputNode获取更直接、更安全
    // 因为它们最终是连接的
    AVAudioFormat *mainMixerOutputFormat = [mainMixer outputFormatForBus:0];
    NSLog(@"主混音器输出格式: %@", mainMixerOutputFormat);

    // 或者你想要的是输入格式（对于outputNode来说，inputFormatForBus:0才是它从mainMixer接收的格式）
    AVAudioFormat *outputNodeInputFormat = [outputNode inputFormatForBus:0];
    NSLog(@"输出节点输入格式: %@", outputNodeInputFormat);
    
//    AVAudioFormat *mainMixFormat = [self.engine outputNode].inputFormatForBus:0];
    
    [self.engine connect:self.playerNode to:self.engine.mainMixerNode format:outputNodeInputFormat];
}

#pragma mark - Public API

- (void)startPlayerFromURL:(NSURL *)url
                    codec:(NSInteger)codec
                 channels:(int)numChannels
              interleaved:(BOOL)interleaved
               sampleRate:(long)sampleRate
               bufferSize:(long)bufferSize {
    [self stop];

    self.sourceURL = url;
    self.m_sampleRate = sampleRate;
    self.m_numChannels = numChannels;
    self.isStreaming = ![url isFileURL];
    [self startPlaybackFromFile:url];

//    dispatch_async(self.stateQueue, ^{
////
////        if (self.isStreaming) {
////            [self startStreamingFromNetwork:url];
////        } else {
////            [self startPlaybackFromFile:url];
////        }
//    });
}

//- (void)startPlayerFromBuffer:(NSData *)dataBuffer {
//    // 仅支持 float PCM
//    [self stop];
//
//    dispatch_async(self.stateQueue, ^{
//        AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:self.m_sampleRate channels:self.m_numChannels];
//        AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:(UInt32)(dataBuffer.length / sizeof(float) / self.m_numChannels)];
//        buffer.frameLength = buffer.frameCapacity;
//
//        float * const * channelData = buffer.floatChannelData;
//        const float *src = (float *)dataBuffer.bytes;
//        int frameLen = (int)buffer.frameLength;
//        for (int c = 0; c < self.m_numChannels; c++) {
//            for (int i = 0; i < frameLen; i++) {
//                channelData[c][i] = src[i * self.m_numChannels + c];
//            }
//        }
//
//        // 处理
//        NSMutableData *rawData = [[NSMutableData alloc] initWithBytes:buffer.floatChannelData length:buffer.byteLength];
//        NSData *processed = [self.audioProcessor processAudioFrameFloat:rawData sampleRate:self.m_sampleRate channels:self.m_numChannels];
//        float *proc = (float *)processed.bytes;
//        for (int c = 0; c < self.m_numChannels; c++) {
//            memcpy(channelData[c], proc + c * frameLen, frameLen * sizeof(float));
//        }
//
//        dispatch_async(dispatch_get_main_queue(), ^{
//            [self.playerNode scheduleBuffer:buffer atTime:nil options:0 completionHandler:nil];
//            [self.playerNode play];
//            [self startPositionUpdates];
//        });
//    });
//}

#pragma mark - File & Stream Playback

- (void)startPlaybackFromFile:(NSURL *)fileURL {
    NSError *error = nil;
    self.audioFile = [[AVAudioFile alloc] initForReading:fileURL error:&error];
    if (error) {
        dispatch_async(dispatch_get_main_queue(), ^{
//            [flautoPlayer audioPlayerDidFailWithError:error];
        });
        return;
    }

    [self scheduleAndPlayFromCurrentPosition];
}

- (void)startStreamingFromNetwork:(NSURL *)url {
    NSURL *cached = [self cachedFileURLForURL:url];
    if ([[NSFileManager defaultManager] fileExistsAtPath:cached.path]) {
        [self startPlaybackFromFile:cached];
    } else {
        [self downloadAndCache:url completion:^(NSURL *localURL) {
            if (localURL) {
                self.cachedFileURL = localURL;
                [self startPlaybackFromFile:localURL];
            } else {
//                [flautoPlayer audioPlayerDidFailWithError:[NSError errorWithDomain:@"Network" code:-1001 userInfo:@{NSLocalizedDescriptionKey: @"Download failed"}]];
            }
        }];
    }
}

- (void)scheduleAndPlayFromCurrentPosition {
    AVAudioFormat *format = self.audioFile.processingFormat;
    AVAudioFrameCount capacity = 4096;

    dispatch_async(self.processingQueue, ^{
        while (YES) {
            if (self.audioFile.framePosition >= self.audioFile.length) break;

            AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:capacity];
            NSError *error = nil;
            if (![self.audioFile readIntoBuffer:buffer error:&error]) {
                NSLog(@"Read error: %@", error);
                break;
            }
            if (buffer.frameLength == 0) break;

            // 提取数据
            float * const * channelData = buffer.floatChannelData;
            int ch = (int)buffer.format.channelCount;
            int frames = (int)buffer.frameLength;
            size_t bytes = frames * sizeof(float) * ch;

            NSMutableData *rawData = [[NSMutableData alloc] initWithLength:bytes];
            float *raw = (float *)[rawData mutableBytes];
            for (int c = 0; c < ch; c++) {
                memcpy(raw + c * frames, channelData[c], frames * sizeof(float));
            }

            // 处理
            
            NSData *processed = [self.audioProcessor processAudioFrameFloat:rawData sampleRate:self.m_sampleRate channels:self.m_numChannels];
            float *proc = (float *)processed.bytes;

            // 写回
            for (int c = 0; c < ch; c++) {
                memcpy(channelData[c], proc + c * frames, frames * sizeof(float));
            }

            // ✅ 同步调度 + completionBlock 保活
            __block AVAudioPCMBuffer *strongBuffer = buffer;
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self.playerNode scheduleBuffer:strongBuffer atTime:nil options:AVAudioPlayerNodeBufferInterrupts completionCallbackType:AVAudioPlayerNodeCompletionDataPlayedBack completionHandler:^(AVAudioPlayerNodeCompletionCallbackType callbackType) {
                    if (callbackType == AVAudioPlayerNodeCompletionDataPlayedBack) {
                           NSLog(@"缓冲区播放完成");
                           // 处理播放完成逻辑
                       } else if (callbackType == AVAudioPlayerNodeCompletionDataConsumed) {
                           NSLog(@"缓冲区被消耗（可能被中断）");
                       }
                    strongBuffer = nil;
                }];
            });

            // 第一块播完后开始播放
            dispatch_async(dispatch_get_main_queue(), ^{
                static dispatch_once_t onceToken;
                dispatch_once(&onceToken, ^{
                    [self.playerNode play];
                    [self startPositionUpdates];
                });
            });
        }

        dispatch_async(dispatch_get_main_queue(), ^{
//            [flautoPlayer audioPlayerDidFinishPlaying];
        });
    });
}

#pragma mark - Control

- (bool)play {
    __block bool result = NO;
    dispatch_sync(self.stateQueue, ^{
        if ([self.playerNode isPlaying]) return;
        [self.playerNode play];
        result = YES;
    });
    return result;
}

- (bool)resume {
    return [self play];
}

- (bool)pause {
    __block bool result = NO;
    dispatch_sync(self.stateQueue, ^{
        if (![self.playerNode isPlaying]) return;
        [self.playerNode pause];
        result = YES;
    });
    [self stopPositionUpdates];
    return result;
}

- (void)stop {
    [self.playerNode stop];
    [self.engine stop];
//    [self.playerNode removeAllInputs]; // 清理连接
    self.audioFile = nil;
    [self stopPositionUpdates];
}

- (bool)seek:(double)pos {
    __block bool success = NO;
    dispatch_sync(self.stateQueue, ^{
        if (!self.audioFile) return;

        double targetSec = pos / 1000.0;
        AVAudioFramePosition targetFrame = (AVAudioFramePosition)(targetSec * self.audioFile.processingFormat.sampleRate);

        if (targetFrame >= self.audioFile.length) return;

        [self.playerNode stop];
        [self.engine stop];

        [self.audioFile setFramePosition:targetFrame];

        [self.engine prepare];
        [self.engine startAndReturnError:nil];

        // 重新开始调度
        [self scheduleAndPlayFromCurrentPosition];
        success = YES;
    });
    return success;
}

#pragma mark - Status

- (t_PLAYER_STATE)getStatus {
    __block t_PLAYER_STATE state = PLAYER_IS_STOPPED;
    dispatch_sync(self.stateQueue, ^{
        if (!self.playerNode || ![self.engine isRunning]) {
            state = PLAYER_IS_STOPPED;
        } else if ([self.playerNode isPlaying]) {
            state = PLAYER_IS_PLAYING;
        } else {
            state = PLAYER_IS_PAUSED;
        }
    });
    return state;
}

- (long)getPosition {
    float time = 0;
    dispatch_sync(self.stateQueue, ^{
//        time = (float)self.playerNode.lastRenderTime.sampleTime / self.playerNode.outputFormatForBus(0).sampleRate;
    });
    return (long)(time * 1000.0);
}

- (long)getDuration {
    __block long duration = 0;
    dispatch_sync(self.stateQueue, ^{
        if (self.audioFile) {
//            duration = (long)(self.audioFile.duration * 1000);
        }
    });
    return duration;
}

#pragma mark - Audio Params

- (bool)setVolume:(double)volume fadeDuration:(NSTimeInterval)fadeDuration {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (fadeDuration == 0) {
            self.playerNode.volume = (float)volume;
        } else {
//            [self.playerNode fadeVolumeTo:(float)volume duration:fadeDuration];
        }
    });
    return YES;
}

- (bool)setPan:(double)pan {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.playerNode.pan = (float)pan;
    });
    return YES;
}

- (bool)setSpeed:(double)speed {
    dispatch_async(dispatch_get_main_queue(), ^{
//        self.playerNode.playbackRate = (float)speed;
    });
    return YES;
}

#pragma mark - Position Updates

- (void)startPositionUpdates {
    [self stopPositionUpdates];
    self.positionTimer = [CADisplayLink displayLinkWithTarget:self selector:@selector(updatePosition)];
    [self.positionTimer addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)updatePosition {
    long pos = [self getPosition];
//    [flautoPlayer audioPlayerUpdatePosition:pos];
}

- (void)stopPositionUpdates {
    if (self.positionTimer) {
        [self.positionTimer invalidate];
        self.positionTimer = nil;
    }
}

#pragma mark - Helpers

- (NSURL *)cachedFileURLForURL:(NSURL *)url {
    NSString *fileName = [url.lastPathComponent length] > 0 ? url.lastPathComponent : @"stream.aac";
    NSString *path = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:fileName];
    return [NSURL fileURLWithPath:path];
}

- (void)downloadAndCache:(NSURL *)url completion:(void(^)(NSURL *))completion {
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDownloadTask *task = [session downloadTaskWithURL:url completionHandler:^(NSURL *loc, NSURLResponse *res, NSError *err) {
        if (!err && loc) {
            NSURL *cached = [self cachedFileURLForURL:url];
            [[NSFileManager defaultManager] copyItemAtURL:loc toURL:cached error:nil];
            completion(cached);
        } else {
            completion(nil);
        }
    }];
    [task resume];
}

@end
