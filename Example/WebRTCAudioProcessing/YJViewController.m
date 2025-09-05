//
//  YJViewController.m
//  WebRTCAudioProcessing
//
//  Created by yjking10 on 09/05/2025.
//  Copyright (c) 2025 yjking10. All rights reserved.
//

#import "YJViewController.h"
#import "AudioProcessingWrapper.h"
#define DEFAULT_BLOCK_MS 10
#define DEFAULT_RATE 16000
#define DEFAULT_CHANNELS 2
@interface YJViewController ()
@property (strong, nonatomic) AudioProcessingWrapper *apWrapper;

@end

@implementation YJViewController


- (void)viewDidLoad {
    [super viewDidLoad];
    
    


    self.apWrapper =[[AudioProcessingWrapper alloc] init];
    
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
