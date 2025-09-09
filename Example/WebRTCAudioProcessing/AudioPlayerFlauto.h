// AudioPlayerFlauto.h
#import <AVFoundation/AVFoundation.h>

typedef NS_ENUM(NSInteger, t_PLAYER_STATE) {
    PLAYER_IS_STOPPED,
    PLAYER_IS_PLAYING,
    PLAYER_IS_PAUSED
};

@class FlautoPlayer;

@interface AudioPlayerFlauto : NSObject

- (instancetype)init:(FlautoPlayer*)owner;

// 播放源
- (void)startPlayerFromURL:(NSURL*)url
                    codec:(NSInteger)codec
                 channels:(int)numChannels
              interleaved:(BOOL)interleaved
               sampleRate:(long)sampleRate
               bufferSize:(long)bufferSize;

- (void)startPlayerFromBuffer:(NSData*)dataBuffer; // PCM only

// 控制
- (bool)play;
- (bool)pause;
- (void)stop;
- (bool)resume;
- (bool)seek:(double)pos; // 毫秒

// 状态
- (t_PLAYER_STATE)getStatus;
- (long)getPosition; // 毫秒
- (long)getDuration; // 毫秒

// 音频参数
- (bool)setVolume:(double)volume fadeDuration:(NSTimeInterval)fadeDuration;
- (bool)setPan:(double)pan;
- (bool)setSpeed:(double)speed;

@end
