//
//  AudioProcessingWrapperPool.m
//  ApmDemo
//
//  Created by YJ on 2025/8/13.
//

#import "AudioProcessingWrapperPool.h"


@implementation AudioProcessingWrapperPool {
    NSMutableDictionary<NSString *, AudioProcessingWrapper *> *_instances;
}

+ (instancetype)shared {
    static AudioProcessingWrapperPool *pool;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        pool = [[AudioProcessingWrapperPool alloc] init];
    });
    return pool;
}

- (instancetype)init {
    if (self = [super init]) {
        _instances = [NSMutableDictionary dictionary];
    }
    return self;
}

- (AudioProcessingWrapper *)wrapperForId:(NSString *)processorId {
    AudioProcessingWrapper *wrapper = _instances[processorId];
    if (!wrapper) {
        wrapper = [[AudioProcessingWrapper alloc] init];
        _instances[processorId] = wrapper;
    }
    return wrapper;
}

- (void)disposeWrapperForId:(NSString *)processorId {
    if (processorId) {
        [_instances removeObjectForKey:processorId];
        NSLog(@"AudioProcessingWrapper for id=%@ disposed", processorId);
    }
}

 
@end
