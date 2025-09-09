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
#import "AudioPlayerFlauto.h"
#define DEFAULT_BLOCK_MS 10
#define DEFAULT_RATE 16000
#define DEFAULT_CHANNELS 2

@interface YJViewController ()
{
    AudioPlayerFlauto * _flautoPlayer;
    
    
    
}
@property (strong, nonatomic) AudioProcessingWrapper *apWrapper;

@end

@implementation YJViewController


- (void)viewDidLoad {
    [super viewDidLoad];
    
    


    self.apWrapper =[[AudioProcessingWrapper alloc] init];
    
    _flautoPlayer = [ [AudioPlayerFlauto alloc] init];

    
}


- (IBAction)play:(id)sender {
    
    NSString *audioFileURL = @"https://resource.datauseful.com/app/test/REC_0001.MP3";

    

    // 获取沙盒 Documents 路径
    NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    // 拼接目标文件路径
    NSString *filePath = [docsDir stringByAppendingPathComponent:@"REC_0001.MP3"];

    // 判断文件是否已存在
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSLog(@"文件已存在，直接使用: %@", filePath);
        [_flautoPlayer startPlayerFromURL:[NSURL URLWithString:audioFileURL] codec:0 channels:2 interleaved:YES sampleRate:16000 bufferSize:4096];
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
                    [_flautoPlayer startPlayerFromURL:[NSURL URLWithString:audioFileURL] codec:0 channels:2 interleaved:YES sampleRate:16000 bufferSize:4096];

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
