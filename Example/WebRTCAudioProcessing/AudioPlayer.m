// AudioPlayer.m
#import "AudioPlayer.h"
#import "AudioProcessingWrapper.h"


@interface AudioPlayer ()

@property (nonatomic, strong) AVAudioEngine *audioEngine;
@property (nonatomic, strong) AVAudioPlayerNode *playerNode;
@property (nonatomic, strong) AVAudioFile *audioFile;
@property (nonatomic, strong) AudioProcessingWrapper *audioProcessor;
@property (nonatomic, assign) BOOL isTapInstalled;
@property (nonatomic, assign) NSTimeInterval currentTimeValue;
@property (nonatomic, assign) NSTimeInterval durationValue;
@property (nonatomic, strong) NSTimer *progressTimer;

@end

@implementation AudioPlayer

- (instancetype)init {
    self = [super init];
    if (self) {
        _audioEngine = [[AVAudioEngine alloc] init];
        _playerNode = [[AVAudioPlayerNode alloc] init];
        _audioProcessor = [[AudioProcessingWrapper alloc] init];
        _isPlaying = NO;
        _isTapInstalled = NO;
        _currentTimeValue = 0;
        _durationValue = 0;
        
        // 先配置音频会话
        [self setupAudioSession];
        
        // 附加节点到音频引擎
        [self attachNodes];
    }
    return self;
}

- (void)setupAudioSession {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;
    
    // 使用Playback类别，支持后台播放
    BOOL success = [session setCategory:AVAudioSessionCategoryPlayback
                                   mode:AVAudioSessionModeDefault
                                options:AVAudioSessionCategoryOptionAllowBluetoothA2DP |
                                         AVAudioSessionCategoryOptionAllowAirPlay
                                  error:&error];
    
    if (!success || error) {
        NSLog(@"配置音频会话失败: %@", error ? error.localizedDescription : @"Unknown error");
        // 尝试使用基本配置
        [session setCategory:AVAudioSessionCategoryPlayback error:nil];
    }
    
    success = [session setActive:YES error:&error];
    if (!success || error) {
        NSLog(@"激活音频会话失败: %@", error ? error.localizedDescription : @"Unknown error");
    }
}

- (void)attachNodes {
    // 将播放器节点附加到音频引擎
    [_audioEngine attachNode:_playerNode];
    
    // 立即连接到主混音器，使用默认格式
    // 先使用nil格式让系统自动处理，稍后再根据音频文件格式重新连接
    [_audioEngine connect:_playerNode to:_audioEngine.mainMixerNode format:nil];
    
    NSLog(@"音频引擎节点附加完成");
    NSLog(@"输入节点: %@", _audioEngine.inputNode);
    NSLog(@"输出节点: %@", _audioEngine.outputNode);
}

- (void)startAudioEngineIfNeeded {
    if (!_audioEngine.isRunning) {
        NSError *error = nil;
        BOOL success = [_audioEngine startAndReturnError:&error];
        
        if (!success || error) {
            NSLog(@"启动音频引擎失败: %@", error ? error.localizedDescription : @"Unknown error");
            
            // 尝试重新配置音频会话
//            [self reinitializeAudioSession];
            
            // 再次尝试启动
            success = [_audioEngine startAndReturnError:&error];
            if (!success || error) {
                NSLog(@"第二次启动音频引擎仍然失败: %@", error ? error.localizedDescription : @"Unknown error");
            }
        } else {
            NSLog(@"音频引擎启动成功");
        }
    }
}

- (void)reinitializeAudioSession {
//    AVAudioSession *session = [AVAudioSession sharedInstance];
//    
//    // 先停用当前会话
//    [session setActive:NO error:nil];
//    
//    // 等待片刻
//    [NSThread sleepForTimeInterval:0.1];
//    
//    // 重新配置
//    [session setCategory:AVAudioSessionCategoryPlayback error:nil];
//    [session setActive:YES error:nil];
//    
//    NSLog(@"音频会话重新初始化完成");
}

- (void)playLocalAudio:(NSURL *)fileURL {
    NSError *error = nil;
    self.audioFile = [[AVAudioFile alloc] initForReading:fileURL error:&error];
    
    if (error || !self.audioFile) {
        NSLog(@"读取音频文件失败: %@", error ? error.localizedDescription : @"文件不存在");
        return;
    }
    
    // 计算时长
    _durationValue = self.audioFile.length / self.audioFile.processingFormat.sampleRate;
    
    NSLog(@"音频文件格式: %@", self.audioFile.processingFormat);
    NSLog(@"文件时长: %.2f秒", _durationValue);
    
    // 停止当前播放
    [self stop];
    
    // 确保音频引擎运行
    [self startAudioEngineIfNeeded];
    
    // 移除之前的tap（如果存在）
    [self removeTap];
    
    // 重新连接节点，使用音频文件的实际格式
    // 先断开现有连接
    [_audioEngine disconnectNodeInput:_audioEngine.mainMixerNode];
    
    // 重新连接，使用文件格式
    [_audioEngine connect:_playerNode to:_audioEngine.mainMixerNode format:self.audioFile.processingFormat];
    
    // 安装tap进行实时音频处理
    [self installTap];
    
    // 安排播放文件
    __weak typeof(self) weakSelf = self;
    [self.playerNode scheduleFile:self.audioFile atTime:nil completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                strongSelf->_isPlaying = NO;
                [strongSelf stopProgressTimer];
                NSLog(@"播放完成");
                
                // 发送播放完成通知
                [[NSNotificationCenter defaultCenter] postNotificationName:@"AudioPlaybackFinished" object:nil];
            }
        });
    }];
    
    // 开始播放
    [self play];
}

- (void)installTap {
    if (self.isTapInstalled) {
        return;
    }
    
    // 获取主混音器的输入格式
    AVAudioFormat *mainMixerInputFormat = [_audioEngine.mainMixerNode inputFormatForBus:0];
    NSLog(@"混音器输入格式: %@", mainMixerInputFormat);
    
    if (!mainMixerInputFormat) {
        NSLog(@"无法获取混音器输入格式");
        return;
    }
    
    // 在主混音器上安装tap
    [_audioEngine.mainMixerNode installTapOnBus:0
                                      bufferSize:1024
                                          format:mainMixerInputFormat
                                           block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
        [self.audioProcessor processBuffer:buffer];
    }];
    
    self.isTapInstalled = YES;
    NSLog(@"Tap安装成功");
}

- (void)removeTap {
    if (self.isTapInstalled) {
        [_audioEngine.mainMixerNode removeTapOnBus:0];
        self.isTapInstalled = NO;
        NSLog(@"Tap已移除");
    }
}

- (void)startProgressTimer {
    [self stopProgressTimer];
    
    self.progressTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                         target:self
                                                       selector:@selector(updateProgress)
                                                       userInfo:nil
                                                        repeats:YES];
}

- (void)stopProgressTimer {
    if (self.progressTimer) {
        [self.progressTimer invalidate];
        self.progressTimer = nil;
    }
}

- (void)updateProgress {
    if (self.isPlaying && self.audioFile) {
        // 获取播放器节点的当前时间
        AVAudioTime *nodeTime = self.playerNode.lastRenderTime;
        AVAudioTime *playerTime = [self.playerNode playerTimeForNodeTime:nodeTime];
        
        if (playerTime) {
            _currentTimeValue = (double)playerTime.sampleTime / self.audioFile.processingFormat.sampleRate;
        }
    }
}

- (NSTimeInterval)currentTime {
    return _currentTimeValue;
}

- (NSTimeInterval)duration {
    return _durationValue;
}

- (void)playRemoteAudio:(NSURL *)url {
    if (!url) {
        NSLog(@"无效的URL");
        return;
    }
    
    NSLog(@"开始下载远程音频: %@", url.absoluteString);
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *audioData = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil];
        if (audioData) {
            // 保存到临时文件
            NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"temp_audio_%f.mp3", [NSDate timeIntervalSinceReferenceDate]]];
            BOOL success = [audioData writeToFile:tempPath atomically:YES];
            
            if (success) {
                NSURL *tempFileURL = [NSURL fileURLWithPath:tempPath];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self playLocalAudio:tempFileURL];
                });
            } else {
                NSLog(@"保存临时文件失败");
            }
        } else {
            NSLog(@"下载音频文件失败");
        }
    });
}

- (void)play {
    if (!self.isPlaying) {
        [self startAudioEngineIfNeeded];
        [self.playerNode play];
        _isPlaying = YES;
        [self startProgressTimer];
        NSLog(@"开始播放");
    }
}

- (void)pause {
    if (self.isPlaying) {
        [self.playerNode pause];
        _isPlaying = NO;
        [self stopProgressTimer];
        NSLog(@"暂停播放");
    }
}

- (void)stop {
    [self.playerNode stop];
    _isPlaying = NO;
    [self stopProgressTimer];
    _currentTimeValue = 0;
    NSLog(@"停止播放");
}

- (void)seekToTime:(NSTimeInterval)time {
    if (!self.audioFile || self.audioFile.length == 0) {
        return;
    }
    
    AVAudioFramePosition targetFrame = (AVAudioFramePosition)(time * self.audioFile.processingFormat.sampleRate);
    targetFrame = MAX(0, MIN(targetFrame, self.audioFile.length));
    
    BOOL wasPlaying = self.isPlaying;
    [self.playerNode stop];
    
    __weak typeof(self) weakSelf = self;
    [self.playerNode scheduleSegment:self.audioFile
                       startingFrame:targetFrame
                          frameCount:(AVAudioFrameCount)(self.audioFile.length - targetFrame)
                              atTime:nil
                   completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && wasPlaying) {
                [strongSelf play];
            }
        });
    }];
    
    _currentTimeValue = time;
}

//- (void)setNoiseSuppressionEnabled:(BOOL)noiseSuppressionEnabled {
//    _noiseSuppressionEnabled = noiseSuppressionEnabled;
//    self.audioProcessor.noiseSuppressionEnabled = noiseSuppressionEnabled;
//    NSLog(@"降噪功能: %@", noiseSuppressionEnabled ? @"启用" : @"禁用");
//}
//
//- (BOOL)noiseSuppressionEnabled {
//    return self.audioProcessor.noiseSuppressionEnabled;
//}

- (void)dealloc {
    [self stop];
    [self removeTap];
    
    if (_audioEngine.isRunning) {
        [_audioEngine stop];
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    NSLog(@"AudioPlayer dealloc");
}

@end
