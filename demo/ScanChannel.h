//
//  ScanChannel.h
//  DTV
//
//  Created by NS on 2018/2/5.
//  Copyright © 2018年 SFT. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SysModel.h"

#define streamBufferSize 188 * 200

typedef void(^ScanCompleteBlock)(id table, id param);
typedef void(^FailBlock)(NSString *errorInfo);
typedef void(^ProgressBlock)(double progress, NSString *info);

typedef void(^BufferCallbackBlock)(void *buf, unsigned int bufsize);

typedef void(^CompleteBlock)(BOOL success, NSString *errorInfo);


@class Program, ProgramTable;
@interface ScanChannel : NSObject
+ (instancetype)shareInstance;

- (void)scanWithSysModels:(NSArray *)models progress:(ProgressBlock)progressBlock callback:(ScanCompleteBlock)completeblock fail:(FailBlock)failblock;

- (void)stopScan;

#if TestPauseScan
- (void)pauseScan:(BOOL)isPaused;
#endif

- (void)filterStream:(Program *)program block:(BOOL)block bufferCallback:(BufferCallbackBlock)callback complete:(CompleteBlock)completeblock;

- (void)stopFilterStream;

@property (assign, nonatomic) BOOL is_initialized;      ///< 网络改变时, 需要重置为NO, 同时需设置preSysmode = DTV_Sysmode_MAX(is_started_mode需设置为NO);

@property (strong, nonatomic) ProgramTable *programTable;   ///< permanently use for per scanned result


@end
