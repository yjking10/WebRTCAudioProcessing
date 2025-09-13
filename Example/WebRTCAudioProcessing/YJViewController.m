//
//  YJViewController.m
//  WebRTCAudioProcessing
//
//  Created by yjking10 on 09/05/2025.
//  Copyright (c) 2025 yjking10. All rights reserved.
//

#import "YJViewController.h"
//#import "AudioProcessingWrapper.h"
#import <WebRTCAudioProcessing/AudioProcessingWrapper.h>

#define DEFAULT_BLOCK_MS 10
#define DEFAULT_RATE 16000
#define DEFAULT_CHANNELS 2

#import <AVFoundation/AVFoundation.h>
#import "NoiseReducedPlayer.h"
#import "AudioPlayer.h"

//#import "PlayerViewModel.h"

#import "PlayerViewModel2.h"
#import "YJAudioPlayer.h"

@interface YJViewController ()
{
    
    
    
}
@property (strong, nonatomic) AudioProcessingWrapper *apWrapper;

@property (strong, nonatomic) AVAudioEngine *audioEngine;
@property (nonatomic, strong) NoiseReducedPlayer * noiseReducedPlayer;

//@property (nonatomic, strong) PlayerViewModel * playerViewModel;
@property (nonatomic, strong) PlayerViewModel2 * playerViewModel2;
@property (nonatomic, strong) YJAudioPlayer * yjAudioPlayer;

@end

@implementation YJViewController


- (void)viewDidLoad {
    [super viewDidLoad];
    NSError *error;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback error:&error];
    [session setActive:YES error:&error];
    
//    _audioEngine = [[AVAudioEngine alloc] init];
    
    // 创建播放器实例
//    AudioPlayer *audioPlayer = [[AudioPlayer alloc] init];
    // 播放本地音频
//    NSURL *url = [[NSBundle mainBundle] URLForResource:@"REC_0001" withExtension:@"MP3"];
//    NSURL *url = [[NSBundle mainBundle] URLForResource:@"test-call" withExtension:@"WAV"];
//
//    [audioPlayer playLocalAudio:url];
//
//    // 启用降噪
//    audioPlayer.noiseSuppressionEnabled = YES;
//
//    // 开始播放
//    [audioPlayer play];
    
    
//    self.apWrapper =[[AudioProcessingWrapper alloc] init];
//    
//    
    _noiseReducedPlayer = [[NoiseReducedPlayer alloc] init];
//    
//    
//    _playerViewModel = [[PlayerViewModel alloc] init];
    
//    _playerViewModel2 = [[PlayerViewModel2 alloc] init];

    _yjAudioPlayer = [[YJAudioPlayer alloc] init];
}


- (IBAction)play:(id)sender {
        NSURL *fileURL = [[NSBundle mainBundle] URLForResource:@"REC_0001" withExtension:@"MP3"];

    [_yjAudioPlayer setupAudioUrl:fileURL];
    [_yjAudioPlayer playOrPause];
    
    return;

    
    [_playerViewModel2 playOrPause];
    
    return;
    
    [self demo2];
    return;
    NSString *audioFileURL = @"https://resource.datauseful.com/app/test/REC_0001.MP3";
    
    
    
    // 获取沙盒 Documents 路径
    NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    // 拼接目标文件路径
    NSString *filePath = [docsDir stringByAppendingPathComponent:@"REC_0001.MP3"];
    
    // 判断文件是否已存在
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSLog(@"文件已存在，直接使用: %@", filePath);
        //        [_flautoPlayer startPlayerFromURL:[NSURL URLWithString:audioFileURL] codec:0 channels:2 interleaved:YES sampleRate:16000 bufferSize:4096];
        //            [_flautoPlayer startPlayerCodec: 0 fromURI:filePath fromDataBuffer:nil channels:2 interleaved:YES sampleRate:16000 bufferSize:4096];
        
    } else {
        NSLog(@"文件不存在，开始下载...");
        
        NSURL *url = [NSURL URLWithString:audioFileURL];
        NSURLSessionDataTask *downloadTask = [[NSURLSession sharedSession]
                                              dataTaskWithURL:url
                                              completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                NSLog(@"下载失败: %@", error);
                return;
            }
            
            // 写入沙盒
            NSError *writeError = nil;
            BOOL success = [data writeToFile:filePath options:NSDataWritingAtomic error:&writeError];
            if (success) {
                NSLog(@"下载并保存成功，路径: %@", filePath);
                //                [_flautoPlayer startPlayerFromURL:[NSURL URLWithString:audioFileURL] codec:0 channels:2 interleaved:YES sampleRate:16000 bufferSize:4096];
                
            } else {
                NSLog(@"写入失败: %@", writeError);
            }
        }];
        
        [downloadTask resume];
    }
    
    // 开启远程控制事件（比如锁屏时控制播放）
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    //
    //
    ////    t_CODEC d = mp3;
    //
    //    NSString*audioFileURL = @"https://resource.datauseful.com/app/test/REC_0001.MP3";
    //
    //
    //
    //
    //    NSURLSessionDataTask *downloadTask = [[NSURLSession sharedSession]
    //            dataTaskWithURL:[NSURL URLWithString:audioFileURL] completionHandler:
    //            ^(NSData* data, NSURLResponse *response, NSError* error)
    //            {
    //
    //        [self->_flautoPlayer startPlayerCodec:mp3 fromURI:nil fromDataBuffer:data channels:2 interleaved:YES sampleRate:16000 bufferSize:2976];
    //
    //
    //            }];
    //    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    //    [downloadTask resume];
    
    //    [_flautoPlayer startPlayerCodec: mp3 fromURI:audioFileURL fromDataBuffer:nil channels:2 interleaved:YES sampleRate:16000 bufferSize:2976];
    
    
}

- (void)demo2{
//    NSURL *url = [[NSBundle mainBundle] URLForResource:@"1752599658" withExtension:@"mp3"];
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"REC_0001" withExtension:@"MP3"];

    [_noiseReducedPlayer playFile0:url];
    
}





- (void)demo1{
    
    AVAudioPlayerNode *player = [[AVAudioPlayerNode alloc] init];
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"REC_0001" withExtension:@"MP3"];
    NSError *error;
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&error];
    if (error) {
        NSLog(@"%@", [error localizedDescription]);
        return;
    }
    [self.audioEngine attachNode:player];
    [self.audioEngine connect:player to:self.audioEngine.mainMixerNode format:file.processingFormat];
    [player scheduleFile:file atTime:nil completionHandler:^{
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.audioEngine.isRunning) {
                [self.audioEngine stop];
            }
        });
        
    }];
    
    [self.audioEngine prepare];
    [self.audioEngine startAndReturnError:&error];
    if (error) {
        NSLog(@"%@", [error localizedDescription]);
    }
    
    [player play];

}




- (IBAction)audioProgcessing:(id)sender {
    NSString *filename = @"REC_0001.raw";
    NSString *path = [[NSBundle mainBundle] pathForResource:filename.stringByDeletingPathExtension
                                                   ofType:filename.pathExtension];

    if (!path) {
        NSLog(@"Error: Could not find file %@ in bundle", filename);
        return;
    }

    NSFileHandle *recFile = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!recFile) {
        NSLog(@"Error: Could not open file for reading: %@", path);
        return;
    }

    // Create output file path (in Documents directory)
    NSString *outputFilename = @"processed_REC_0001.raw";
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject];
    NSString *outputPath = [documentsDirectory stringByAppendingPathComponent:outputFilename];

    // Create output file (overwrite if exists)
    [[NSFileManager defaultManager] createFileAtPath:outputPath contents:nil attributes:nil];
    NSFileHandle *aecFile = [NSFileHandle fileHandleForWritingAtPath:outputPath];
    if (!aecFile) {
        NSLog(@"Error: Could not open file for writing: %@", outputPath);
        [recFile closeFile];
        return;
    }

    @try {
        const size_t bufferSize = DEFAULT_RATE * DEFAULT_BLOCK_MS / 1000 * DEFAULT_CHANNELS * sizeof(int16_t);
        
        while (YES) {
            @autoreleasepool {
                NSData *data = [recFile readDataOfLength:bufferSize];
                if ([data length] == 0) {
                    break; // Reached end of file
                }
                
                NSData *resData = [self.apWrapper processAudioFrame:data sampleRate:DEFAULT_RATE channels:DEFAULT_CHANNELS];
                
                // Process the data if needed (currently just copying)
                [aecFile writeData:resData];
            }
        }
        
        NSLog(@"File processing completed. Output saved to: %@", outputPath);
    }
    @catch (NSException *exception) {
        NSLog(@"Error during file processing: %@", exception);
    }
    @finally {
        [recFile closeFile];
        [aecFile closeFile];
    }
    

}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
