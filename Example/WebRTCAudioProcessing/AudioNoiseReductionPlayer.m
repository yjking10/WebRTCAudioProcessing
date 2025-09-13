#import "AudioNoiseReductionPlayer.h"
#import "NoiseReductionNode.h"
#import "AudioProcessingWrapper.h"

@interface AudioNoiseReductionPlayer ()

@property (nonatomic, strong) AVAudioEngine *audioEngine;
@property (nonatomic, strong) AVAudioPlayerNode *playerNode;
@property (nonatomic, strong) NoiseReductionNode *noiseReductionNode;
@property (nonatomic, strong) AVAudioFile *audioFile;
@property (nonatomic, assign) AVAudioFramePosition currentFrame;
@property (nonatomic, assign) AVAudioFramePosition totalFrames;
@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, assign) BOOL isPrepared;
@property (nonatomic, strong) AVAudioFormat *targetFormat;

@end

@implementation AudioNoiseReductionPlayer

- (instancetype)initWithAudioFileURL:(NSURL *)fileURL {
    self = [super init];
    if (self) {
        _isNoiseReductionEnabled = YES;
        _volume = 1.0f;
        _isPlaying = NO;
        _isPrepared = NO;
        
        [self setupAudioSession];
        [self setupAudioFile:fileURL];
        [self setupTargetFormat];
        [self setupAudioEngine];
        
        _isPrepared = YES;
    }
    return self;
}

- (void)setupAudioSession {
    NSError *error = nil;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:&error];
    if (error) {
        NSLog(@"Error setting audio session category: %@", error);
    }
    
    [audioSession setActive:YES error:&error];
    if (error) {
        NSLog(@"Error activating audio session: %@", error);
    }
}

- (void)setupAudioFile:(NSURL *)fileURL {
    NSError *error = nil;
    _audioFile = [[AVAudioFile alloc] initForReading:fileURL error:&error];
    if (error) {
        NSLog(@"Error loading audio file: %@", error);
        if (_errorHandler) {
            _errorHandler(error);
        }
        return;
    }
    
    _totalFrames = _audioFile.length;
    _duration = _totalFrames / _audioFile.processingFormat.sampleRate;
    
    NSLog(@"Audio file loaded: %@, duration: %.2fs, format: %@",
          fileURL.lastPathComponent, _duration, _audioFile.processingFormat);
}

- (void)setupTargetFormat {
    // 使用WebRTC推荐的格式：float32, non-interleaved
    _targetFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                     sampleRate:_audioFile.processingFormat.sampleRate
                                                       channels:_audioFile.processingFormat.channelCount
                                                    interleaved:NO];
}

- (void)setupAudioEngine {
    _audioEngine = [[AVAudioEngine alloc] init];
    _playerNode = [[AVAudioPlayerNode alloc] init];
    
    // 创建降噪节点
    _noiseReductionNode = [[NoiseReductionNode alloc] initWithFormat:_targetFormat];
    _noiseReductionNode.enabled = _isNoiseReductionEnabled;
    
    // 附加节点到音频引擎
    [_audioEngine attachNode:_playerNode];
    [_audioEngine attachNode:_noiseReductionNode];
    
    // 连接节点：播放器 → 降噪 → 混音器
    // 如果需要格式转换，音频引擎会自动处理
    [_audioEngine connect:_playerNode to:_noiseReductionNode format:nil]; // 自动格式处理
    [_audioEngine connect:_noiseReductionNode to:_audioEngine.mainMixerNode format:nil];
    
    // 设置音量
    _playerNode.volume = _volume;
    
    // 准备音频引擎
    [_audioEngine prepare];
    
    NSLog(@"Audio engine setup complete");
}

- (void)scheduleAudioFile {
    if (_currentFrame >= _totalFrames) {
        return;
    }
    
    // 计算合适的缓冲区大小（约100ms）
    AVAudioFrameCount preferredBufferSize = _targetFormat.sampleRate * 0.1;
    preferredBufferSize = MIN(preferredBufferSize, (AVAudioFrameCount)(_totalFrames - _currentFrame));
    
    __weak typeof(self) weakSelf = self;
    [_playerNode scheduleSegment:_audioFile
                   startingFrame:_currentFrame
                       frameCount:preferredBufferSize
                           atTime:nil
                completionHandler:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        strongSelf->_currentFrame += preferredBufferSize;
        
        if (strongSelf->_currentFrame < strongSelf->_totalFrames) {
            // 继续调度下一段
            [strongSelf scheduleAudioFile];
        } else {
            // 播放完成
            strongSelf->_isPlaying = NO;
            if (strongSelf.completionHandler) {
                strongSelf.completionHandler();
            }
        }
    }];
}

#pragma mark - Public Methods

- (void)play {
    if (_isPlaying || !_isPrepared) {
        return;
    }
    
    if (_currentFrame >= _totalFrames) {
        _currentFrame = 0; // 重新开始
    }
    
    NSError *error = nil;
    if (![_audioEngine startAndReturnError:&error]) {
        NSLog(@"Error starting audio engine: %@", error);
        if (_errorHandler) {
            _errorHandler(error);
        }
        return;
    }
    
    if (_currentFrame == 0) {
        [self scheduleAudioFile];
    }
    
    [_playerNode play];
    _isPlaying = YES;
    
    NSLog(@"Playback started at position: %.2fs", self.currentTime);
}

- (void)pause {
    if (!_isPlaying) {
        return;
    }
    
    // 获取当前播放位置
    AVAudioTime *nodeTime = _playerNode.lastRenderTime;
    if (nodeTime) {
        AVAudioTime *playerTime = [_playerNode playerTimeForNodeTime:nodeTime];
        if (playerTime) {
            _currentFrame = playerTime.sampleTime;
        }
    }
    
    [_playerNode pause];
    _isPlaying = NO;
    
    NSLog(@"Playback paused at position: %.2fs", self.currentTime);
}

- (void)stop {
    [_playerNode stop];
    [_audioEngine stop];
    _currentFrame = 0;
    _isPlaying = NO;
    
    NSLog(@"Playback stopped");
}

- (void)seekToTime:(NSTimeInterval)time {
    [self seekToTime:time completion:nil];
}

- (void)seekToTime:(NSTimeInterval)time completion:(void (^)(BOOL))completion {
    BOOL wasPlaying = _isPlaying;
    
    if (wasPlaying) {
        [self pause];
    }
    
    AVAudioFramePosition targetFrame = time * _audioFile.processingFormat.sampleRate;
    targetFrame = MAX(0, MIN(targetFrame, _totalFrames));
    _currentFrame = targetFrame;
    
    // 清除当前调度
    [_playerNode stop];
    
    // 重新调度
    [self scheduleAudioFile];
    
    if (wasPlaying) {
        [self play];
    }
    
    if (completion) {
        completion(YES);
    }
    
    NSLog(@"Seek to: %.2fs", time);
}

- (NSTimeInterval)currentTime {
    if (_isPlaying) {
        AVAudioTime *nodeTime = _playerNode.lastRenderTime;
        if (nodeTime) {
            AVAudioTime *playerTime = [_playerNode playerTimeForNodeTime:nodeTime];
            if (playerTime) {
                return playerTime.sampleTime / _audioFile.processingFormat.sampleRate;
            }
        }
    }
    return _currentFrame / _audioFile.processingFormat.sampleRate;
}

- (void)setIsNoiseReductionEnabled:(BOOL)isNoiseReductionEnabled {
    _isNoiseReductionEnabled = isNoiseReductionEnabled;
    _noiseReductionNode.enabled = isNoiseReductionEnabled;
}

- (void)setVolume:(float)volume {
    _volume = volume;
    _playerNode.volume = volume;
}

#pragma mark - Performance Monitoring

- (CFTimeInterval)lastProcessingTime {
    return _noiseReductionNode.lastProcessingTime;
}

- (CFTimeInterval)maxProcessingTime {
    return _noiseReductionNode.maxProcessingTime;
}

- (void)resetPerformanceStats {
    [_noiseReductionNode updateProcessingStats];
}

#pragma mark - Cleanup

- (void)dealloc {
    [self stop];
    [_audioEngine stop];
    
    NSLog(@"AudioNoiseReductionPlayer dealloc");
}

@end
