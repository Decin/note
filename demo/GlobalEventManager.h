//
//  GlobalEventManager.h
//  WiFiDisk
//
//  Created by NS on 2017/9/5.
//  Copyright © 2017年 Decin. All rights reserved.
//

#import <Foundation/Foundation.h>

#define SINGAL_PowerNotice @"SINGAL_PowerNotice"


@interface GlobalEventManager : NSObject

+ (instancetype)shareInstance;

- (void)registerPeriodEvent:(void(^)(void))block andFireDuration:(int)secends;


/**
 注册事件

 @param block 事件block
 @param secends 执行周期, 3的倍数
 @param singal 事件标识
 */
- (void)registerPeriodEvent:(void(^)(void))block andFireDuration:(int)secends singal:(NSString *)singal;
- (void)removePeriodEventWithSingal:(NSString *)singal;

/**
 电源提醒
 */
- (void)openPowerNoticeEvent;
- (void)openPowerNoticeEventWithProcessBlock:(void(^)(BOOL success, int batlevel, BOOL isCharging))block;
- (void)closePowerNoticeEvent;
- (BOOL)checkConnection;
@end
