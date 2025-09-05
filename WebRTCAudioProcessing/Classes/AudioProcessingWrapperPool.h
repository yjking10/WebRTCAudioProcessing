//
//  AudioProcessingWrapperPool.h
//  ApmDemo
//
//  Created by YJ on 2025/8/13.
//

#import <Foundation/Foundation.h>
#import "AudioProcessingWrapper.h"

NS_ASSUME_NONNULL_BEGIN

@interface AudioProcessingWrapperPool : NSObject


+ (instancetype)shared;


- (AudioProcessingWrapper *)wrapperForId:(NSString *)processorId ;

- (void)disposeWrapperForId:(NSString *)processorId;

@end

NS_ASSUME_NONNULL_END
