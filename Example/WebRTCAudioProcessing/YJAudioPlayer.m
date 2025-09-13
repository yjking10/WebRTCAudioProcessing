//
//  PlayerViewModel2.m
//  WebRTCAudioProcessing_Example
//
//  Created by YJ on 2025/9/10.
//  Copyright © 2025 yjking10. All rights reserved.
//

#import "YJAudioPlayer.h"


#import <QuartzCore/CADisplayLink.h>
#import "AudioProcessingWrapper.h"



@interface YJAudioPlayer ()
{
    AVAudioEngine *_engine;
    AVAudioPlayerNode *_player;
    AVAudioUnitTimePitch *_timeEffect;

    CADisplayLink *_displayLink;

    AVAudioUnitEQ* eqUnit; // Add EQ unit


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


@implementation YJAudioPlayer

- (instancetype)init {
    if (self = [super init]) {
        _isPlaying = NO;
        _isPlayerReady = NO;
        _playerProgress = 0;
        _playerTime = [PlayerTime zero];
        _meterLevel = 0;

        _needsFileScheduled = YES;
        _wrapper = [[AudioProcessingWrapper alloc] init];

        _engine = [[AVAudioEngine alloc] init];
        _player = [[AVAudioPlayerNode alloc] init];
        _timeEffect = [[AVAudioUnitTimePitch alloc] init];

        _needsFileScheduled = YES;
        _seekFrame = 0;
        _currentPosition = 0;

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
- (void)setupAudioUrl:(NSURL  *)fileURL {
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


- (void)setupAudioPath:(NSString *)filePath {
//    NSURL *fileURL = [[NSBundle mainBundle] URLForResource:@"Intro" withExtension:@"mp3"];

    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    if (!fileURL) return;

    [self setupAudioUrl:fileURL];
}

// Add a new method to setup EQ
- (AVAudioUnitEQ*)setupEQWithGain:(float)gain {
    AVAudioUnitEQ* eqNode = [[AVAudioUnitEQ alloc] initWithNumberOfBands:3];
    
    // Band 1: Low frequency noise reduction (e.g., humming)
    eqNode.bands[0].filterType = AVAudioUnitEQFilterTypeParametric;
    eqNode.bands[0].frequency = 200;
    eqNode.bands[0].bandwidth = 1.0;
    eqNode.bands[0].gain = gain;
    eqNode.bands[0].bypass = NO;
    
    // Band 2: Mid frequency noise reduction (e.g., keyboard sounds)
    eqNode.bands[1].filterType = AVAudioUnitEQFilterTypeParametric;
    eqNode.bands[1].frequency = 1000;
    eqNode.bands[1].bandwidth = 0.5;
    eqNode.bands[1].gain = gain;
    eqNode.bands[1].bypass = NO;
    
    // Band 3: High frequency noise reduction (e.g., hissing)
    eqNode.bands[2].filterType = AVAudioUnitEQFilterTypeHighShelf;
    eqNode.bands[2].frequency = 3000;
    eqNode.bands[2].gain = gain;
    eqNode.bands[2].bypass = NO;
    
    return eqNode;
}

- (void)configureEngine:(AVAudioFormat *)format {
//    eqUnit = [self setupEQWithGain:4.0];
//    [_engine attachNode:eqUnit];
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

- (void)audioProcessBuffer{
    double sampleRate = _audioFile.processingFormat.sampleRate;
    if (sampleRate <= 0) {
        sampleRate = _audioFile.fileFormat.sampleRate; // 兜底
    }
    
    
    int channels =_audioFile.processingFormat.channelCount;
    AVAudioFormat *processingFormat = [[AVAudioFormat alloc]
                                       initWithCommonFormat:AVAudioPCMFormatFloat32
                                       sampleRate:sampleRate
                                       channels:channels
                                       interleaved:NO];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        AVAudioFrameCount bufferSize = 8192; // 4096一次性读大点
        int framePer10ms = sampleRate / 100; // 每 10ms 的采样点数

        NSLog(@"framePer10ms=%d", framePer10ms);
        while (true) {
            AVAudioPCMBuffer *pcmBuffer =
                [[AVAudioPCMBuffer alloc] initWithPCMFormat:processingFormat
                                              frameCapacity:bufferSize];
            NSError *readError = nil;
            BOOL success = [_audioFile readIntoBuffer:pcmBuffer error:&readError];
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
                

                
//                            int channels = (int)pcmBuffer.format.channelCount;
//                            int sampleRate = (int)pcmBuffer.format.sampleRate;
//                            int frameCount = (int)pcmBuffer.frameLength;
////                            NSLog(@"channels=%d sampleRate=%d frameCount=%d",channels,sampleRate,frameCount);


                // === 降噪 ===
                [self.wrapper processBuffer:blockBuffer];

                // === 播放 ===
                [_player scheduleBuffer:blockBuffer completionHandler:nil];

                offset += framePer10ms;
            }
        }
    });
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

- (void)setPlaybackRate:(float)playbackRate {

    _timeEffect.rate = playbackRate;
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
    
    return;
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
