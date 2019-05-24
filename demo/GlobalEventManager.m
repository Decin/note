//
//  GlobalEventManager.m
//  WiFiDisk
//
//  Created by NS on 2017/9/5.
//  Copyright © 2017年 Decin. All rights reserved.
//

#import "GlobalEventManager.h"
#import "DeviceInterface.h"
#import "UIAlertController+Blocks.h"

#define PowerNoticeEventDuration (1 * 60)

@interface GlobalEvent : NSObject
@property (strong, nonatomic) NSString *singal;         ///< 标识
@property (assign, nonatomic) int duration;             ///< 执行周期
@property (strong, nonatomic) void(^eventHanlder)(void);    ///< 事件处理

@end

@implementation GlobalEvent

@end


@interface GlobalEventManager()

@property (assign, nonatomic) int timerTimeStamp;

/**
 @{
    @(secends) : @[globalEvent0, globalEvent1, ...],
 };
 */
@property (strong, nonatomic) NSMutableDictionary *eventDictM;

@property (weak  , nonatomic) UIAlertController *alertController;

@property (strong, nonatomic) dispatch_queue_t event_queue;

@property (assign, nonatomic) BOOL status_Connection;
@end

@implementation GlobalEventManager {
    dispatch_source_t _timer;
}

- (NSMutableDictionary *)eventDictM {
    if (!_eventDictM) {
        _eventDictM = [NSMutableDictionary dictionary];
    }
    return _eventDictM;
}

static GlobalEventManager *_instance;
+ (id)allocWithZone:(NSZone *)zone
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [super allocWithZone:zone];
    });
    return _instance;
}

+ (instancetype)shareInstance
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [[self alloc] init];
    });
    return _instance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.timerTimeStamp = 0;
        self.event_queue = dispatch_queue_create("event_queue", DISPATCH_QUEUE_SERIAL);
        [self startTimer];
    }
    return self;
}

- (void)dealloc {
    [self stopTimer];
}

- (void)startTimer {
    __weak typeof(self) weakSelf = self;
    
    dispatch_source_set_timer(self.timer, DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC, 0 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(self.timer, ^{
        weakSelf.timerTimeStamp++;
        NSLog(@"%@--%s--weakSelf.timerTimeStamp : %d", [self class], __func__, weakSelf.timerTimeStamp);

        for (NSNumber *num in self.eventDictM.allKeys) {
            if (weakSelf.timerTimeStamp % num.intValue == 0) {
                for (GlobalEvent *globalEvent in weakSelf.eventDictM[num]) {
                    /* FIXME: 异步 */
                    if (globalEvent.eventHanlder) globalEvent.eventHanlder();
                }
            }
        }
        
    });
    dispatch_resume(self.timer);
}

- (void)stopTimer {
    if (_timer) {
        dispatch_source_cancel(_timer);
        _timer = NULL;
    }
}

- (dispatch_source_t)timer {
    if (!_timer) {
        _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.event_queue);
    }
    return _timer;
}

#pragma mark - Genaral

/**
 普通的简单保存blcok, 暂未使用
 */
- (void)registerPeriodEvent:(void(^)(void))block andFireDuration:(int)secends {
    if ([self.eventDictM.allKeys containsObject:@(secends)]) {
        NSMutableArray *arrM = [self.eventDictM objectForKey:@(secends)];
        if(block) [arrM addObject:block];
    } else {
        [self.eventDictM setObject:[NSMutableArray arrayWithObject:block] forKey:@(secends)];
    }
}

- (void)registerPeriodEvent:(void(^)(void))block andFireDuration:(int)secends singal:(NSString *)singal {

    if ([self.eventDictM.allKeys containsObject:@(secends)]) {
        
        NSMutableArray *arrM = [self.eventDictM objectForKey:@(secends)];
        BOOL isExist = NO;
        for (GlobalEvent *globalEvent in arrM) {
            if ([globalEvent.singal isEqualToString:singal]) {
                isExist = YES;
                globalEvent.duration = secends;
                globalEvent.singal = singal;
                globalEvent.eventHanlder = block;
                break;
            };
        }
        
        if (!isExist) {
            GlobalEvent *globalEvent = [[GlobalEvent alloc] init];
            if(block) globalEvent.eventHanlder = block;
            globalEvent.duration = secends;
            globalEvent.singal = singal;
            [arrM addObject:globalEvent];
        }
    } else {
        GlobalEvent *globalEvent = [[GlobalEvent alloc] init];
        if(block) globalEvent.eventHanlder = block;
        globalEvent.duration = secends;
        globalEvent.singal = singal;
        
        [self.eventDictM setObject:[NSMutableArray arrayWithObject:globalEvent] forKey:@(secends)];
    }
    
}

- (void)removePeriodEventWithSingal:(NSString *)singal {
    [self.eventDictM.allValues enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [obj enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(GlobalEvent *globalEvent, NSUInteger idx, BOOL * _Nonnull stop) {
            if ([globalEvent.singal isEqualToString:singal]) {
                [obj removeObject:globalEvent];
                *stop = YES;
            }
        }];
    }];
}

#pragma mark - Power
- (void)openPowerNoticeEvent {
    [self openPowerNoticeEventWithProcessBlock:nil];
}

- (void)openPowerNoticeEventWithProcessBlock:(void(^)(BOOL success, int batlevel, BOOL isCharging))block {
    
    __block BOOL isMatchDevice = NO;
    [[NetworkUtil shareInstance] startGlobalMonitoringRepeat:YES showViewController:nil changeBlock:^(BOOL isMatch, NSString *desc) {
        NSLog(@"%@--%s--isMatchDevice : %d", [self class], __func__, isMatch);

        isMatchDevice = isMatch;
        self.status_Connection = isMatch;
    }];
    
    __weak typeof(self) weakSelf = self;
    [self registerPeriodEvent:^{
        if (!isMatchDevice) return;

        [[DeviceInterface shareInstance] sft_get_battery_level:^(BOOL success, int batlevel, BOOL isCharging) {
            if (!success) return ;  // 失败就退出
            
            NSLog(@"%@--%s--batlevel : %d, isCharging : %d", [self class], __func__, batlevel, isCharging);
            dispatch_async_UISafe(^{
                if (block) block(success, batlevel, isCharging);
            })
            
            if (!isCharging && batlevel <= 5) {
                // 没在充电才提醒
                NSString *message = [NSString stringWithFormat:NSLocalizedString(@"less than %d%%", nil), batlevel <= 5 ? 5 : 10];
                
                dispatch_async_UISafe(^{
                    if (weakSelf.alertController)
                    {
                        [weakSelf.alertController dismissViewControllerAnimated:YES completion:^{
                            weakSelf.alertController = [UIAlertController showAlertInViewController:[UIApplication sharedApplication].keyWindow.rootViewController withTitle:NSLocalizedString(@"Device Low battery !", nil) message:message cancelButtonTitle:NSLocalizedString(@"Confirm", nil) destructiveButtonTitle:nil otherButtonTitles:nil tapBlock:nil];
                        }];
                    }
                    else {
                        weakSelf.alertController = [UIAlertController showAlertInViewController:[UIApplication sharedApplication].keyWindow.rootViewController withTitle:NSLocalizedString(@"Device Low battery !", nil) message:message cancelButtonTitle:NSLocalizedString(@"Confirm", nil) destructiveButtonTitle:nil otherButtonTitles:nil tapBlock:nil];
                    }
                });
            }
            else {
                dispatch_async_UISafe(^{
                    if (weakSelf.alertController)
                    {
                        [weakSelf.alertController dismissViewControllerAnimated:YES completion:^{
                        }];
                    }
                });
            }
            
        }];
    } andFireDuration:PowerNoticeEventDuration singal:SINGAL_PowerNotice];
}

- (void)closePowerNoticeEvent {
    [[NetworkUtil shareInstance] stopGlobalMonitoring];
    [self removePeriodEventWithSingal:SINGAL_PowerNotice];
}

- (BOOL)checkConnection {
    return self.status_Connection;
}


@end
