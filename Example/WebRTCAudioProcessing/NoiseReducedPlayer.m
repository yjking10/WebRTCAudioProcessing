#import <AVFoundation/AVFoundation.h>
#import "AudioProcessingWrapper.h"
#import "NoiseReducedPlayer.h"
@interface NoiseReducedPlayer()
{
    AVAudioEngine *_audioEngine;
    AVAudioPlayerNode *_player;
    AVAudioUnitTimePitch *_timeEffect;

    CADisplayLink *_displayLink;



    AVAudioFile *_audioFile;
    double _audioSampleRate;
    double _audioLengthSeconds;

    AVAudioFramePosition _seekFrame;
    AVAudioFramePosition _currentPosition;
    AVAudioFramePosition _audioLengthSamples;
}
@property (nonatomic, assign) BOOL needsFileScheduled;

@property (nonatomic, strong) AudioProcessingWrapper *wrapper;
@end

@implementation NoiseReducedPlayer


- (instancetype)init {
    if (self = [super init]) {
        _isPlaying = NO;
        _isPlayerReady = NO;
        _playerProgress = 0;
        _playerTime = [PlayerTime zero];
        _meterLevel = 0;
        _needsFileScheduled = YES;
        _seekFrame = 0;
        _currentPosition = 0;
        
        _audioEngine = [[AVAudioEngine alloc] init];
        _player = [[AVAudioPlayerNode alloc] init];
        _timeEffect = [[AVAudioUnitTimePitch alloc] init];
        _wrapper = [[AudioProcessingWrapper alloc] init];
        
        [_audioEngine attachNode:_player];
        [_audioEngine connect:_player to:_audioEngine.mainMixerNode format:nil];
    }
    return self;
}



- (void)setupAudio {
//    NSURL *fileURL = [[NSBundle mainBundle] URLForResource:@"Intro" withExtension:@"mp3"];

    NSURL *fileURL = [[NSBundle mainBundle] URLForResource:@"REC_0001" withExtension:@"MP3"];
    if (!fileURL) return;

    NSError *error = nil;
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:fileURL error:&error];
    if (error) {
        NSLog(@"Error reading audio file: %@", error.localizedDescription);
        return;
    }

    AVAudioFormat *format = file.processingFormat;
    _audioLengthSamples = file.length;
    _audioSampleRate = format.sampleRate;
    _audioLengthSeconds = (double)_audioLengthSamples / _audioSampleRate;
    _audioFile = file;

    [self configureEngine:format];
}


- (void)configureEngine:(AVAudioFormat *)format {
    [_audioEngine attachNode:_player];
    [_audioEngine attachNode:_timeEffect];

    [_audioEngine connect:_player to:_timeEffect format:format];
    [_audioEngine connect:_timeEffect to:_audioEngine.mainMixerNode format:format];

    [_audioEngine prepare];

    NSError *error = nil;
    [_audioEngine startAndReturnError:&error];
    if (error) {
        NSLog(@"Error starting engine: %@", error.localizedDescription);
        return;
    }

    [self scheduleAudioFile];
    self.isPlayerReady = YES;
}
- (void)scheduleAudioFile {
    if (!_audioFile || !_needsFileScheduled) return;

    _needsFileScheduled = NO;
    _seekFrame = 0;

    __weak typeof(self) weakSelf = self;
    [_player scheduleFile:_audioFile atTime:nil completionHandler:^{
        weakSelf.needsFileScheduled = YES;
    }];
}

- (void)playOrPause {
    self.isPlaying = !self.isPlaying;

    if (_player.isPlaying) {
        _displayLink.paused = YES;
        
        [_player pause];
    } else {
        _displayLink.paused = NO;

        if (_needsFileScheduled) {
            [self scheduleAudioFile];
        }
        [_player play];
    }
}



- (void)skipForwards:(BOOL)forwards {
    double timeToSeek = forwards ? 10 : -10;
    [self seek:timeToSeek];
}
#pragma mark - Controls

- (void)seek:(double)time {
    if (!_audioFile) return;

    AVAudioFramePosition offset = (AVAudioFramePosition)(time * _audioSampleRate);
    _seekFrame = _currentPosition + offset;
    _seekFrame = MAX(_seekFrame, 0);
    _seekFrame = MIN(_seekFrame, _audioLengthSamples);
    _currentPosition = _seekFrame;

    BOOL wasPlaying = _player.isPlaying;
    [_player stop];

    if (_currentPosition < _audioLengthSamples) {
        [self updateDisplay];
        _needsFileScheduled = NO;

        AVAudioFrameCount frameCount = (AVAudioFrameCount)(_audioLengthSamples - _seekFrame);
        __weak typeof(self) weakSelf = self;
        [_player scheduleSegment:_audioFile startingFrame:_seekFrame frameCount:frameCount atTime:nil completionHandler:^{
            weakSelf.needsFileScheduled = YES;
        }];

        if (wasPlaying) {
            [_player play];
        }
    }
}
#pragma mark - Rate & Pitch

- (void)setPlaybackRate:(double)playbackRate{
    _timeEffect.rate =playbackRate;
}

//- (void)setPlaybackPitchIndex:(NSInteger)playbackPitchIndex {
//    _playbackPitchIndex = playbackPitchIndex;
//    PlaybackValue *selected = self.allPlaybackPitches[playbackPitchIndex];
//    _timeEffect.pitch = 1200 * (float)selected.value;
//}

#pragma mark - Display

- (void)setupDisplayLink {
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateDisplay)];
    [_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    _displayLink.paused = YES;
}

- (void)updateDisplay {
    AVAudioTime *lastRenderTime = _player.lastRenderTime;
    AVAudioTime *playerTime = lastRenderTime ? [_player playerTimeForNodeTime:lastRenderTime] : nil;

    AVAudioFramePosition currentFrame = playerTime ? playerTime.sampleTime : 0;
    _currentPosition = currentFrame + _seekFrame;
    _currentPosition = MAX(_currentPosition, 0);
    _currentPosition = MIN(_currentPosition, _audioLengthSamples);

    if (_currentPosition >= _audioLengthSamples) {
        [_player stop];
        _seekFrame = 0;
        _currentPosition = 0;
        self.isPlaying = NO;
        _displayLink.paused = YES;
//        [self disconnectVolumeTap];
    }

    self.playerProgress = (double)_currentPosition / (double)_audioLengthSamples;
    double time = (double)_currentPosition / _audioSampleRate;
    self.playerTime = [[PlayerTime alloc] init];
    self.playerTime.elapsedTime = time;
    self.playerTime.remainingTime = _audioLengthSeconds - time;
}

/// 速度变快
- (void)playFile0:(NSURL *)url {
    NSError *error = nil;
    
    // 检查文件是否存在
    if (![[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
        NSLog(@"File does not exist: %@", url);
        return;
    }
    
    // ✅ 关键修复：初始化时指定目标格式，自动转换
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url
                                               commonFormat:AVAudioPCMFormatFloat32
                                                   interleaved:NO
                                                       error:&error];
    if (error || !file) {
        NSLog(@"File error: %@", error);
        return;
    }

    // ✅ 获取统一的处理格式（由 AVAudioFile 转换后提供）
    AVAudioFormat *processingFormat = file.processingFormat;
    double sampleRate = processingFormat.sampleRate;
    int channels = (int)processingFormat.channelCount;
    
    NSLog(@"文件原始格式: %@", [file.fileFormat description]);
    NSLog(@"处理格式: %@", [processingFormat description]);

    // 计算 10ms 对应的帧数
    NSUInteger framePer10ms = (NSUInteger)round(sampleRate * 0.01);
    if (framePer10ms == 0) framePer10ms = 1;

    // 缓冲队列
    NSMutableArray<AVAudioPCMBuffer *> *pendingBuffers = [NSMutableArray array];

    // 渲染块
    AVAudioSourceNodeRenderBlock renderBlock =
    ^OSStatus(BOOL *isSilence,
              const AudioTimeStamp *timestamp,
              AVAudioFrameCount frameCount,
              AudioBufferList *outputData) {
        
        NSLog(@"frameCount=%d", frameCount);

        // 初始化输出为静音
        for (UInt32 i = 0; i < outputData->mNumberBuffers; i++) {
            memset(outputData->mBuffers[i].mData, 0, outputData->mBuffers[i].mDataByteSize);
        }
        *isSilence = YES;

        AVAudioFrameCount framesRemaining = frameCount;
        AVAudioFrameCount outputOffset = 0;
        

        while (framesRemaining > 0) {
            // 填充缓冲队列
            while (pendingBuffers.count == 0) {
                AVAudioPCMBuffer *readBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:processingFormat
                                                                            frameCapacity:1024];
                NSError *readErr = nil;
                BOOL ok = [file readIntoBuffer:readBuffer frameCount:readBuffer.frameCapacity error:&readErr];
                NSLog(@"读文件 %d",ok);
                if (!ok || readErr || readBuffer.frameLength == 0) {
                    NSLog(@"-------文件结束------,%@", [readErr description]);
                    break; // 文件结束
                }

                [pendingBuffers addObject:readBuffer];
            }

            if (pendingBuffers.count == 0) {
                NSLog(@"无数据，保持静音");
                break; // 无数据，保持静音
            }

            AVAudioPCMBuffer *frontBuffer = pendingBuffers.firstObject;
            AVAudioFrameCount availableFrames = frontBuffer.frameLength;

            NSLog(@"frontBuffer: %@, availableFrames=%d", [frontBuffer.format  description], availableFrames);
            
            
            // 创建处理块（不足时补零到 10ms）
            AVAudioPCMBuffer *processBuffer;
            AVAudioFrameCount processFrameLength;

          
            if (availableFrames < framePer10ms) {
                // 补零到 10ms
                processBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:processingFormat
                                                              frameCapacity:framePer10ms];
                processBuffer.frameLength = framePer10ms;

                for (UInt32 i = 0; i < processBuffer.audioBufferList->mNumberBuffers; i++) {
                    memcpy(processBuffer.audioBufferList->mBuffers[i].mData,
                           frontBuffer.audioBufferList->mBuffers[i].mData,
                           availableFrames * sizeof(float));
                    // 剩余自动为0
                }

                processFrameLength = availableFrames;
            } else {
                // 截取 10ms
                processBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:processingFormat
                                                              frameCapacity:framePer10ms];
                processBuffer.frameLength = framePer10ms;

                for (UInt32 i = 0; i < processBuffer.audioBufferList->mNumberBuffers; i++) {
                    memcpy(processBuffer.audioBufferList->mBuffers[i].mData,
                           frontBuffer.audioBufferList->mBuffers[i].mData,
                           framePer10ms * sizeof(float));
                }

                processFrameLength = framePer10ms;
            }

            // 降噪处理
            if (self.wrapper) {
                [self.wrapper processBuffer10ms:processBuffer];
            }

            // 拷贝到输出
            AVAudioFrameCount framesToCopy = MIN(framesRemaining, processFrameLength);
            for (UInt32 i = 0; i < outputData->mNumberBuffers && i < processBuffer.audioBufferList->mNumberBuffers; i++) {
                float *src = (float *)processBuffer.audioBufferList->mBuffers[i].mData;
                float *dst = (float *)outputData->mBuffers[i].mData + outputOffset;
                memcpy(dst, src, framesToCopy * sizeof(float));
            }

            // 更新缓冲区
            if (availableFrames > processFrameLength) {
                for (UInt32 i = 0; i < frontBuffer.audioBufferList->mNumberBuffers; i++) {
                    memmove(frontBuffer.audioBufferList->mBuffers[i].mData,
                            (char *)frontBuffer.audioBufferList->mBuffers[i].mData + processFrameLength * sizeof(float),
                            (availableFrames - processFrameLength) * sizeof(float));
                }
                frontBuffer.frameLength = availableFrames - processFrameLength;
            } else {
                [pendingBuffers removeObjectAtIndex:0];
            }

            framesRemaining -= framesToCopy;
            outputOffset += framesToCopy;
            *isSilence = NO;
        }

        return noErr;
    };

    // 创建节点
    AVAudioSourceNode *sourceNode = [[AVAudioSourceNode alloc] initWithFormat:processingFormat
                                                                  renderBlock:renderBlock];
    [_audioEngine attachNode:sourceNode];
    [_audioEngine connect:sourceNode to:_audioEngine.mainMixerNode format:processingFormat];

    // 启动引擎
    [_audioEngine prepare];
    NSError *engineErr = nil;
    if (![_audioEngine startAndReturnError:&engineErr]) {
        NSLog(@"Engine error: %@", engineErr);
        return;
    }

    NSLog(@"✅ 播放开始，采样率: %.0f Hz, 10ms = %lu 帧", sampleRate, (unsigned long)framePer10ms);
}
/// 速度变快
- (void)playFile00:(NSURL *)url {
    NSError *error = nil;
    
    // 检查文件是否存在
    if (![[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
        NSLog(@"File does not exist: %@", url);
        return;
    }
    
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&error];
    if (error || !file) {
        NSLog(@"File error: %@", error);
        return;
    }

    // 获取采样率和声道数
    double sampleRate = file.processingFormat.sampleRate;
    if (sampleRate <= 0) {
        sampleRate = file.fileFormat.sampleRate;
    }
    int channels = (int)file.processingFormat.channelCount;

    // 创建处理格式：Float32、非交错
    AVAudioFormat *processingFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                                      sampleRate:sampleRate
                                                                        channels:channels
                                                                     interleaved:NO];

    // 计算 10ms 对应的帧数（例如 48000Hz → 480 帧）
    NSUInteger framePer10ms = (NSUInteger)round(sampleRate * 0.01);
    if (framePer10ms == 0) framePer10ms = 1; // 安全兜底

    // 缓冲队列：存储从文件读取但尚未处理的数据块
    NSMutableArray<AVAudioPCMBuffer *> *pendingBuffers = [NSMutableArray array];

    // 渲染块
    AVAudioSourceNodeRenderBlock renderBlock =
    ^OSStatus(BOOL *isSilence,
              const AudioTimeStamp *timestamp,
              AVAudioFrameCount frameCount,
              AudioBufferList *outputData) {

        // 初始化输出为静音（安全兜底）
        for (UInt32 i = 0; i < outputData->mNumberBuffers; i++) {
            memset(outputData->mBuffers[i].mData, 0, outputData->mBuffers[i].mDataByteSize);
        }
        *isSilence = YES;
        
        AVAudioFrameCount bufferSize = 8192; // 4096一次性读大点
        int framePer10ms = sampleRate / 100; // 每 10ms 的采样点数

        NSLog(@"framePer10ms=%d", framePer10ms);
        while (true) {
            AVAudioPCMBuffer *pcmBuffer =
                [[AVAudioPCMBuffer alloc] initWithPCMFormat:processingFormat
                                              frameCapacity:bufferSize];
            NSError *readError = nil;
            BOOL success = [file readIntoBuffer:pcmBuffer error:&readError];
            if (!success || pcmBuffer.frameLength == 0) {
                break; // EOF
            }

            int totalFrames = (int)pcmBuffer.frameLength;
            int offset = 0;
            
            NSLog(@"offset=%d, totalFrames=%d",offset, totalFrames);


            while (offset + framePer10ms <= totalFrames) {
                // === 拆出一个 10ms block ===
                AVAudioPCMBuffer *blockBuffer =
                    [[AVAudioPCMBuffer alloc] initWithPCMFormat:processingFormat
                                                  frameCapacity:framePer10ms];
                blockBuffer.frameLength = framePer10ms;
                
                
                for (int c = 0; c < channels; c++) {
                    memcpy(blockBuffer.floatChannelData[c],
                           pcmBuffer.floatChannelData[c] + offset,
                           framePer10ms * sizeof(float));
                }
                

                
                            int channels = (int)pcmBuffer.format.channelCount;
                            int sampleRate = (int)pcmBuffer.format.sampleRate;
                            int frameCount = (int)pcmBuffer.frameLength;
//                            NSLog(@"channels=%d sampleRate=%d frameCount=%d",channels,sampleRate,frameCount);


                // === 降噪 ===
                [self.wrapper processBuffer:blockBuffer];



                offset += framePer10ms;
            }
        }
        
        

        AVAudioFrameCount framesRemaining = frameCount;
        AVAudioFrameCount outputOffset = 0;

        while (framesRemaining > 0) {
            // Step 1: 确保 pendingBuffers 中有数据，至少能凑出一个块（10ms 或剩余数据）
            while (pendingBuffers.count == 0) {
                // 读取一块数据（比如1024帧）
                AVAudioPCMBuffer *readBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:processingFormat
                                                                            frameCapacity:4096];
                NSError *readErr = nil;
                BOOL ok = [file readIntoBuffer:readBuffer frameCount:readBuffer.frameCapacity error:&readErr];

                if (!ok || readErr || readBuffer.frameLength == 0) {
                    // 文件结束，不再读取
                    break;
                }

                [pendingBuffers addObject:readBuffer];
            }

            // Step 2: 如果没有数据了，保持静音退出
            if (pendingBuffers.count == 0) {
                break; // 文件已读完，输出保持静音
            }

            // 获取第一个缓冲区
            AVAudioPCMBuffer *frontBuffer = pendingBuffers.firstObject;
            AVAudioFrameCount availableFrames = frontBuffer.frameLength;

            // 创建 processBuffer：如果不足 10ms，补零到 10ms；否则截取 10ms
            AVAudioPCMBuffer *processBuffer;
            AVAudioFrameCount processFrameLength;

            if (availableFrames < framePer10ms) {
                // 补零到完整 10ms 块（降噪器可能要求固定长度）
                processBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:processingFormat
                                                              frameCapacity:framePer10ms];
                processBuffer.frameLength = framePer10ms; // 自动初始化为0

                // 拷贝有效数据
                for (UInt32 i = 0; i < processBuffer.audioBufferList->mNumberBuffers; i++) {
                    memcpy(processBuffer.audioBufferList->mBuffers[i].mData,
                           frontBuffer.audioBufferList->mBuffers[i].mData,
                           availableFrames * sizeof(float));
                    // 剩余部分保持为0（已由 initWithPCMFormat 初始化）
                }

                processFrameLength = availableFrames; // 实际有效数据长度，用于拷贝到输出
            } else {
                // 截取前 10ms 数据
                processBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:processingFormat
                                                              frameCapacity:framePer10ms];
                processBuffer.frameLength = framePer10ms;

                for (UInt32 i = 0; i < processBuffer.audioBufferList->mNumberBuffers; i++) {
                    memcpy(processBuffer.audioBufferList->mBuffers[i].mData,
                           frontBuffer.audioBufferList->mBuffers[i].mData,
                           framePer10ms * sizeof(float));
                }

                processFrameLength = framePer10ms;
            }

            // Step 3: 交给降噪器处理（输入始终是 10ms 长度）
            if (self.wrapper) {
                [self.wrapper processBuffer10ms:processBuffer];
            }

            // Step 4: 拷贝处理后的数据到输出（最多拷贝 framesRemaining）
            AVAudioFrameCount framesToCopy = MIN(framesRemaining, processFrameLength);
            for (UInt32 i = 0; i < outputData->mNumberBuffers && i < processBuffer.audioBufferList->mNumberBuffers; i++) {
                float *src = (float *)processBuffer.audioBufferList->mBuffers[i].mData;
                float *dst = (float *)outputData->mBuffers[i].mData + outputOffset;
                memcpy(dst, src, framesToCopy * sizeof(float));
            }

            // Step 5: 更新 frontBuffer
            if (availableFrames > processFrameLength) {
                // 剩余数据前移
                for (UInt32 i = 0; i < frontBuffer.audioBufferList->mNumberBuffers; i++) {
                    memmove(frontBuffer.audioBufferList->mBuffers[i].mData,
                            (char *)frontBuffer.audioBufferList->mBuffers[i].mData + processFrameLength * sizeof(float),
                            (availableFrames - processFrameLength) * sizeof(float));
                }
                frontBuffer.frameLength = availableFrames - processFrameLength;
            } else {
                // 该缓冲区已用完，移除
                [pendingBuffers removeObjectAtIndex:0];
            }

            // 更新状态
            framesRemaining -= framesToCopy;
            outputOffset += framesToCopy;
            *isSilence = NO;
        }

        return noErr;
    };

    // 创建并连接节点
    AVAudioSourceNode *sourceNode = [[AVAudioSourceNode alloc] initWithFormat:processingFormat
                                                                  renderBlock:renderBlock];
    [_audioEngine attachNode:sourceNode];
    [_audioEngine connect:sourceNode to:_audioEngine.mainMixerNode format:processingFormat];

    // 启动引擎
    [_audioEngine prepare];
    NSError *engineErr = nil;
    if (![_audioEngine startAndReturnError:&engineErr]) {
        NSLog(@"Engine error: %@", engineErr);
        return;
    }

    NSLog(@"✅ 播放开始，采样率: %.0f Hz, 10ms = %lu 帧", sampleRate, (unsigned long)framePer10ms);
}
- (void)playFile3:(NSURL *)url {
    NSError *error = nil;
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&error];
    if (error || !file) {
        NSLog(@"File error: %@", error);
        return;
    }

    AVAudioFormat *fileFormat = file.processingFormat; // 可能是浮点非交错
    double sampleRate = fileFormat.sampleRate > 0 ? fileFormat.sampleRate : file.fileFormat.sampleRate;
    AVAudioChannelCount channels = fileFormat.channelCount;

    // 统一为 Float32 非交错
    AVAudioFormat *processingFormat =
        [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                         sampleRate:sampleRate
                                           channels:channels
                                        interleaved:NO];


    // 源节点：在渲染回调中从文件读取 -> 降噪 -> 输出到 ioData
   
    AVAudioSourceNodeRenderBlock renderBlock =
    ^OSStatus(BOOL *isSilence,
              const AudioTimeStamp *timestamp,
              AVAudioFrameCount frameCount,
              AudioBufferList *outputData) {

    
        NSLog(@"outputData mNumberBuffers= %d;  frameCount= %d",outputData->mNumberBuffers, frameCount);
        // 准备一个中间 PCMBuffer
        AVAudioPCMBuffer *tempBuf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:processingFormat
                                                                  frameCapacity:frameCount];
        tempBuf.frameLength = frameCount;

        NSError *readErr = nil;
        BOOL ok = [file readIntoBuffer:tempBuf frameCount:frameCount error:&readErr];
        if (!ok || tempBuf.frameLength == 0) {
            // EOF：输出静音
            for (UInt32 i = 0; i < outputData->mNumberBuffers; i++) {
                memset(outputData->mBuffers[i].mData, 0, outputData->mBuffers[i].mDataByteSize);
            }
            *isSilence = YES;
            return noErr;
        }

        // 调用你的降噪
        // 要求：processBuffer 原地修改 tempBuf.floatChannelData[c]
        [self.wrapper processBuffer:tempBuf];
        NSLog(@"------processBuffer-------");

        // 拷贝到 ioData（非交错 float32）
        for (AVAudioChannelCount c = 0; c < channels; c++) {
            float *dst = (float *)outputData->mBuffers[c].mData;
            const float *src = tempBuf.floatChannelData[c];
            memcpy(dst, src, tempBuf.frameLength * sizeof(float));
            outputData->mBuffers[c].mDataByteSize = (UInt32)(tempBuf.frameLength * sizeof(float));
        }

        *isSilence = NO;
        return noErr;
    };
    

    AVAudioSourceNode *sourceNode = [[AVAudioSourceNode alloc] initWithFormat:processingFormat
                                                                  renderBlock:renderBlock];

    [_audioEngine attachNode:sourceNode];
    [_audioEngine connect:sourceNode to:_audioEngine.mainMixerNode format:processingFormat];

    NSError *engineErr = nil;
    [_audioEngine startAndReturnError:&engineErr];
    if (engineErr) {
        NSLog(@"Engine error: %@", engineErr);
        return;
    }
}

- (void)playFile:(NSURL *)url {
    NSError *error = nil;
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&error];
    if (error) {
        NSLog(@"File error: %@", error.localizedDescription);
        return;
    }
    
    NSLog(@"");
    
    double sampleRate = file.processingFormat.sampleRate;
    if (sampleRate <= 0) {
        sampleRate = file.fileFormat.sampleRate; // 兜底
    }
    
    
    int channels =file.processingFormat.channelCount;
    // 强制使用 float32 非交错格式
    AVAudioFormat *processingFormat = [[AVAudioFormat alloc]
                                       initWithCommonFormat:AVAudioPCMFormatFloat32
                                       sampleRate:sampleRate
                                       channels:channels
                                       interleaved:NO];
    
    NSLog(@"processingFormat file.processingFormat.sampleRate=%d, file.processingFormat.channelCount=%d, ",sampleRate,  file.processingFormat.channelCount);
    
    [_audioEngine connect:_player to:_audioEngine.mainMixerNode format:processingFormat];
    [_audioEngine prepare];
    [_audioEngine startAndReturnError:&error];
    if (error) {
        NSLog(@"Engine error: %@", error.localizedDescription);
        return;
    }
    
//    [self scheduleNextBufferFromFile:file format:processingFormat framePerBlock:sampleRate / 100];

    [_player play];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        AVAudioFrameCount bufferSize = 8192; // 4096一次性读大点
        int framePer10ms = sampleRate / 100; // 每 10ms 的采样点数

        NSLog(@"framePer10ms=%d", framePer10ms);
        while (true) {
            AVAudioPCMBuffer *pcmBuffer =
                [[AVAudioPCMBuffer alloc] initWithPCMFormat:processingFormat
                                              frameCapacity:bufferSize];
            NSError *readError = nil;
            BOOL success = [file readIntoBuffer:pcmBuffer error:&readError];
            if (!success || pcmBuffer.frameLength == 0) {
                break; // EOF
            }

            int totalFrames = (int)pcmBuffer.frameLength;
            int offset = 0;
            
            NSLog(@"offset=%d, totalFrames=%d",offset, totalFrames);


            while (offset + framePer10ms <= totalFrames) {
                // === 拆出一个 10ms block ===
                AVAudioPCMBuffer *blockBuffer =
                    [[AVAudioPCMBuffer alloc] initWithPCMFormat:processingFormat
                                                  frameCapacity:framePer10ms];
                blockBuffer.frameLength = framePer10ms;
                
                
                for (int c = 0; c < channels; c++) {
                    memcpy(blockBuffer.floatChannelData[c],
                           pcmBuffer.floatChannelData[c] + offset,
                           framePer10ms * sizeof(float));
                }
                

                
                            int channels = (int)pcmBuffer.format.channelCount;
                            int sampleRate = (int)pcmBuffer.format.sampleRate;
                            int frameCount = (int)pcmBuffer.frameLength;
//                            NSLog(@"channels=%d sampleRate=%d frameCount=%d",channels,sampleRate,frameCount);


                // === 降噪 ===
                [self.wrapper processBuffer:blockBuffer];

                // === 播放 ===
                [_player scheduleBuffer:blockBuffer completionHandler:nil];

                offset += framePer10ms;
            }
        }
    });
}

@end
