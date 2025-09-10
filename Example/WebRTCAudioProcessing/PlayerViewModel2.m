//
//  PlayerViewModel2.m
//  WebRTCAudioProcessing_Example
//
//  Created by YJ on 2025/9/10.
//  Copyright © 2025 yjking10. All rights reserved.
//

#import "PlayerViewModel2.h"


#import <QuartzCore/CADisplayLink.h>
#import "AudioProcessingWrapper.h"





@interface PlayerViewModel2 ()
{
    AVAudioEngine *_engine;
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

//累积 buffer.frameLength 数据，凑够 10ms 再交给 processBuffer10ms
//因为 AVAudioEngine 给你的 buffer 大小未必正好是 10ms（可能是 4096 帧、1024 帧等）。
//所以你需要自己建一个环形缓冲区（或 NSMutableData）去拼接
@property (nonatomic, strong) NSMutableData *pcmCache;

@property (nonatomic, strong) AudioProcessingWrapper *wrapper;
@property (nonatomic, strong) AVAudioConverter *converter;
@property (nonatomic, strong) AVAudioFormat *targetFormat;

@end


@implementation PlayerViewModel2

- (instancetype)init {
    if (self = [super init]) {
        _isPlaying = NO;
        _isPlayerReady = NO;
        _playerProgress = 0;
        _playerTime = [PlayerTime zero];
        _meterLevel = 0;

        _playbackRateIndex = 1;
        _playbackPitchIndex = 1;

        _needsFileScheduled = YES;
        _wrapper = [[AudioProcessingWrapper alloc] init];

        _allPlaybackRates = @[
            [[PlaybackValue alloc] initWithValue:0.5 label:@"0.5x"],
            [[PlaybackValue alloc] initWithValue:1.0 label:@"1x"],
            [[PlaybackValue alloc] initWithValue:1.25 label:@"1.25x"],
            [[PlaybackValue alloc] initWithValue:2.0 label:@"2x"]
        ];

        _allPlaybackPitches = @[
            [[PlaybackValue alloc] initWithValue:-0.5 label:@"-½"],
            [[PlaybackValue alloc] initWithValue:0.0 label:@"0"],
            [[PlaybackValue alloc] initWithValue:0.5 label:@"+½"]
        ];

        _engine = [[AVAudioEngine alloc] init];
        _player = [[AVAudioPlayerNode alloc] init];
        _timeEffect = [[AVAudioUnitTimePitch alloc] init];

        _needsFileScheduled = YES;
        _seekFrame = 0;
        _currentPosition = 0;

        [self setupAudio];
        [self setupDisplayLink];
        NSLog(@"init ok");
    }
    return self;
}

#pragma mark - Public

- (void)playOrPause {
    self.isPlaying = !self.isPlaying;

    if (_player.isPlaying) {
        _displayLink.paused = YES;
        [self disconnectVolumeTap];
        [_player pause];
    } else {
        _displayLink.paused = NO;
        [self connectVolumeTap];

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

#pragma mark - Setup

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
    [_engine attachNode:_player];
    [_engine attachNode:_timeEffect];

    [_engine connect:_player to:_timeEffect format:format];
    [_engine connect:_timeEffect to:_engine.mainMixerNode format:format];

    [_engine prepare];

    NSError *error = nil;
    [_engine startAndReturnError:&error];
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

- (void)setPlaybackRateIndex:(NSInteger)playbackRateIndex {
    _playbackRateIndex = playbackRateIndex;
    PlaybackValue *selected = self.allPlaybackRates[playbackRateIndex];
    _timeEffect.rate = (float)selected.value;
}

- (void)setPlaybackPitchIndex:(NSInteger)playbackPitchIndex {
    _playbackPitchIndex = playbackPitchIndex;
    PlaybackValue *selected = self.allPlaybackPitches[playbackPitchIndex];
    _timeEffect.pitch = 1200 * (float)selected.value;
}

#pragma mark - Metering

- (float)scaledPower:(float)power {
    if (!isfinite(power)) return 0.0;

    float minDb = -80.0;
    if (power < minDb) return 0.0;
    if (power >= 1.0) return 1.0;

    return (fabs(minDb) - fabs(power)) / fabs(minDb);
}

- (void)connectVolumeTap {
    
    
    AVAudioFormat *inputFormat = [_engine.mainMixerNode outputFormatForBus:0];
    
    
    double sampleRate = _audioFile.processingFormat.sampleRate;
    if (sampleRate <= 0) {
        sampleRate = _audioFile.fileFormat.sampleRate; // 兜底
    }
   
    NSLog(@"inputFormat = %@",[inputFormat description] );

    
    int channels =_audioFile.processingFormat.channelCount;
    
    //AVAudioPCMFormatFloat32
    AVAudioCommonFormat commonFormat = inputFormat.commonFormat;
    
    _targetFormat = [[AVAudioFormat alloc]
                                       initWithCommonFormat:commonFormat
                                       sampleRate:sampleRate
                                       channels:channels
                                       interleaved:NO];
    
    // 目标格式：16kHz, 1声道, float32
//    _targetFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:16000 channels:1];
    
    self.converter = [[AVAudioConverter alloc] initFromFormat:inputFormat toFormat:_targetFormat];
    
    int framePer10ms = (int)(_targetFormat.sampleRate * 0.01); // 160
    
    NSLog(@"framePer10ms = %d",framePer10ms );

    self.pcmCache = [NSMutableData data];
    
    [_engine.mainMixerNode installTapOnBus:0
                                bufferSize:4096
                                    format:inputFormat
                                     block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        if (!buffer) return;
        
        NSLog(@"buffer = %@",[buffer.format description ]  );

        
        // 先转换格式
        AVAudioPCMBuffer *convertedBuffer =
            [[AVAudioPCMBuffer alloc] initWithPCMFormat:self->_targetFormat
                                          frameCapacity:(AVAudioFrameCount)framePer10ms];
        
        NSError *error = nil;
        AVAudioConverterInputBlock inputBlock = ^AVAudioBuffer * _Nullable(AVAudioPacketCount inNumberOfPackets,
                                                                           AVAudioConverterInputStatus *outStatus) {
            *outStatus = AVAudioConverterInputStatus_HaveData;
            return buffer;
        };
        [self.converter convertToBuffer:convertedBuffer error:&error withInputFromBlock:inputBlock];
        if (error) {
            NSLog(@"convert error: %@", error);
            return;
        }
        NSLog(@"convertedBuffer = %@",[convertedBuffer.format description ]  );

        // 转成 NSData 累积
        NSUInteger byteCount = convertedBuffer.frameLength * self->_targetFormat.streamDescription->mBytesPerFrame;
        NSData *pcmData = [NSData dataWithBytes:convertedBuffer.floatChannelData[0]
                                         length:byteCount];
        [self.pcmCache appendData:pcmData];
        
        NSUInteger bytesPer10ms = framePer10ms * self->_targetFormat.streamDescription->mBytesPerFrame;
        
        
        NSLog(@"byteCount = %ld, bytesPer10ms=%ld, self.pcmCache.length=%ld",byteCount,  bytesPer10ms, self.pcmCache.length);

        while (self.pcmCache.length >= bytesPer10ms) {
            NSData *chunk = [self.pcmCache subdataWithRange:NSMakeRange(0, bytesPer10ms)];
            [self.pcmCache replaceBytesInRange:NSMakeRange(0, bytesPer10ms) withBytes:NULL length:0];
            
            AVAudioPCMBuffer *chunkBuffer = [[AVAudioPCMBuffer alloc]
                initWithPCMFormat:self->_targetFormat
                    frameCapacity:framePer10ms];
            
            chunkBuffer.frameLength = framePer10ms;
            
            memcpy(chunkBuffer.floatChannelData[0], chunk.bytes, bytesPer10ms);
            
            // 送去降噪
//            [_wrapper processBuffer10ms:chunkBuffer];
        }
    }];
}

- (void)connectVolumeTap11 {
    AVAudioFormat *format = [_engine.mainMixerNode outputFormatForBus:0];
    double sampleRate = format.sampleRate;
    int channels = format.channelCount;
    
//    sampleRate=48000.000000; channels=2; framePer10ms=480

    // 每 10ms 样本数
    int framePer10ms = (int)(sampleRate * 0.01);
    
    NSLog(@"sampleRate=%f; channels=%d; framePer10ms=%d", sampleRate, channels, framePer10ms);

    
    self.pcmCache = [NSMutableData data];
    
    [_engine.mainMixerNode installTapOnBus:0
                                bufferSize:4096
                                    format:format
                                     block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        if (!buffer.floatChannelData) return;
        
        // 每个 buffer 转换成 NSData 存入缓存
        NSUInteger byteCount = buffer.frameLength * format.streamDescription->mBytesPerFrame;
        NSLog(@"byteCount = %ld",byteCount);
        NSData *pcmData = [NSData dataWithBytes:buffer.floatChannelData[0]
                                         length:byteCount];
        [self.pcmCache appendData:pcmData];
        
        // 检查是否 >= 10ms
        NSUInteger bytesPer10ms = framePer10ms * format.streamDescription->mBytesPerFrame;
        NSLog(@"bytesPer10ms = %ld",bytesPer10ms);

        while (self.pcmCache.length >= bytesPer10ms) {
            NSData *chunk = [self.pcmCache subdataWithRange:NSMakeRange(0, bytesPer10ms)];
            [self.pcmCache replaceBytesInRange:NSMakeRange(0, bytesPer10ms) withBytes:NULL length:0];
            
            // 转 AVAudioPCMBuffer 再调用你的处理方法
            AVAudioPCMBuffer *chunkBuffer = [[AVAudioPCMBuffer alloc]
                initWithPCMFormat:format
                    frameCapacity:framePer10ms];
            chunkBuffer.frameLength = framePer10ms;
            
            memcpy(chunkBuffer.floatChannelData[0], chunk.bytes, bytesPer10ms);
            
            [_wrapper processBuffer10ms:chunkBuffer];
            [_player scheduleBuffer:chunkBuffer completionHandler:^{
                
            }];

        }
    }];
}

- (void)connectVolumeTap2 {
    AVAudioFormat *format = [_engine.mainMixerNode outputFormatForBus:0];
    [_engine.mainMixerNode installTapOnBus:0 bufferSize:4096 format:format block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        if (!buffer.floatChannelData) return;
        
        NSLog(@"buffer.frameCapacity=%d,  buffer.format.sampleRate=%d, buffer.format.channelCount=%d, buffer.format.interleaved=%d",buffer.frameCapacity,  buffer.format.sampleRate, buffer.format.channelCount, buffer.format.interleaved);

        float *channelData = buffer.floatChannelData[0];
        
        NSMutableArray *values = [NSMutableArray array];
        
        for (int i = 0; i < buffer.frameLength; i += buffer.stride) {
            [values addObject:@(channelData[i])];
        }

        float sum = 0;
        for (NSNumber *n in values) {
            float v = [n floatValue];
            sum += v * v;
        }
        float rms = sqrt(sum / buffer.frameLength);
        float avgPower = 20 * log10(rms);
        float meter = [self scaledPower:avgPower];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.meterLevel = self.isPlaying ? meter : 0;
        });
    }];
}

- (void)disconnectVolumeTap {
    [_engine.mainMixerNode removeTapOnBus:0];
    self.meterLevel = 0;
}

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
        [self disconnectVolumeTap];
    }

    self.playerProgress = (double)_currentPosition / (double)_audioLengthSamples;
    double time = (double)_currentPosition / _audioSampleRate;
    self.playerTime = [[PlayerTime alloc] init];
    self.playerTime.elapsedTime = time;
    self.playerTime.remainingTime = _audioLengthSeconds - time;
}

@end
