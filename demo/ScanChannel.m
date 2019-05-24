//
//  ScanChannel.m
//  DTV
//
//  Created by NS on 2018/2/5.
//  Copyright © 2018年 SFT. All rights reserved.
//

#import "ScanChannel.h"
#import "ts_scan_program.h"

#import "SandBoxUtil.h"
#import "DeviceInterface.h"

#import "ns_tvclient_interface.h"           ///< 测试, 临时导入
#import "EPGEventItem.h"                    ///< 测试, 临时导入


typedef enum : NSUInteger {
    ScanStateNothing,
    ScanStateScanning,
    ScanStateStopping,
    ScanStateFiltering,
    ScanStateFiltered,
} ScanState;

@interface ScanChannel ()
@property (strong, nonatomic) NSOperationQueue *queue;              ///< 接口调用队列, 保证接口依次调用
@property (strong, nonatomic) NSOperationQueue *control_queue;               ///< 停止切换控制队列

@property (copy, nonatomic) ScanCompleteBlock completeBlock;

@property (assign, nonatomic) BOOL is_stop_scan;

#if TestPauseScan
@property (assign, nonatomic) BOOL is_pause_scan;
#endif

@property (assign, nonatomic) NSInteger scanned_program_count;          ///< 记录已经扫描到的节目数量

@property (strong, nonatomic) ProgramTable *tempProgTable;   ///< temporarily use for per scanning

@property (assign, nonatomic) DTV_Sysmode preSysmode;


@property (assign, nonatomic) ScanState state;               ///< 保证原子性

@property (strong, nonatomic) dispatch_semaphore_t semaphore;

@end

static BOOL is_invoked_callback = YES;                       ///< 记录扫描回调是否已经调用

@implementation ScanChannel


static ScanChannel *_instance;
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
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(dowithAppWillTerminate)
                                                     name:UIApplicationWillTerminateNotification
                                                   object:nil];
        self.queue = [[NSOperationQueue alloc] init];
        self.queue.qualityOfService = NSQualityOfServiceUserInteractive;    // 设置为高优先级
        self.queue.maxConcurrentOperationCount = 1;
        self.queue.name = @"ScanChannelQueue";
        
        self.control_queue = [[NSOperationQueue alloc] init];
        self.control_queue.qualityOfService = NSQualityOfServiceUserInteractive;    // 设置为高优先级
        self.control_queue.maxConcurrentOperationCount = 1;
        self.control_queue.name = @"ScanChannelControlQueue";
        
        self.semaphore = dispatch_semaphore_create(0);
        
        self.scanned_program_count = 0;
        self.preSysmode = DTV_Sysmode_MAX;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (ProgramTable *)programTable {
    if (!_programTable) {
        _programTable = [NSKeyedUnarchiver unarchiveObjectWithFile:[SandBoxUtil scanProgramTableArchiverPath]];
    }
    return _programTable;
}

#pragma mark - Device init
- (void)setIs_initialized:(BOOL)is_initialized {
    _is_initialized = is_initialized;
    
    NSLog(@"%@--%s--is_initialized : %@", [self class], __func__, is_initialized ? @"YES" : @"NO");
    if (_is_initialized == NO) {
        self.preSysmode = DTV_Sysmode_MAX;
    }
}

// init and open tune
- (BOOL)initDeviceAndOpenTune:(FailBlock)failblock {

    //初始化通信环境
    [[DeviceInterface shareInstance] sft_init_communication_environment];
    
    // 查看tvtune open状态
    DeviceStatus b_tune_open_state = [[DeviceInterface shareInstance] sft_tvtune_get_tune_open_state];
    if (b_tune_open_state != DeviceStatusNormal) {
        if (b_tune_open_state == DeviceStatusOccupied) {
            NSLog(@"%@--%s---------error: DeviceStatusOccupied", [self class], __func__);
            [self fireBlock:failblock param1:NSLocalizedString(@"Device is occupied by other user", nil)];
            return NO;
        }
        
        // 调幅开启
        int i = 0;
        BOOL success = NO;
        NSInteger ret = 0;
        while (!success && i < 4) {
            NSLog(@"%@--%s---------tvtune open", [self class], __func__);
            success = [[DeviceInterface shareInstance] sft_tvtune_open:&ret];
            i++;
        }
        if (!success)
            [self fireBlock:failblock param1:[NSString stringWithFormat:@"%@ : %ld", NSLocalizedString(@"open tv timeout", nil), ret]];
//        [self fireBlock:failblock param1:[NSString stringWithFormat:@"%@ : %ld", NSLocalizedString(@"open tv fail", nil), ret]];
        return success;
    }
    else {
        NSLog(@"%@--%s--initDeviceAndOpenTune : %@", [self class], __func__, b_tune_open_state ? @"YES" : @"NO");
        return b_tune_open_state == DeviceStatusNormal;
    }
}

// start dtvmode
- (BOOL)startDtvmode:(DTV_Sysmode)sysmode fail:(FailBlock)failblock {
    
    //检测设备端是否支持当前的 dtv mode
    NSLog(@"%@--%s--%@", [self class], __func__, @"check supported dtvmode------");
    if(![[DeviceInterface shareInstance] sft_is_supported_dtvmode:sysmode]) {
        NSLog(@"device do not support for this dtv system type:%d\n", sysmode);
        [self fireBlock:failblock param1:NSLocalizedString(@"The system mode is not supported", nil)];
        return NO;
    }
    
    // 查看tvtune open状态
    DeviceStatus b_tune_start_state = [[DeviceInterface shareInstance] sft_tvtune_get_tune_start_state];
    if (b_tune_start_state != DeviceStatusNormal) {
        if (b_tune_start_state == DeviceStatusOccupied) {
            NSLog(@"%@--%s---------error: DeviceStatusOccupied", [self class], __func__);
            [self fireBlock:failblock param1:NSLocalizedString(@"Device is occupied by other user", nil)];
            return NO;
        }
        
        
        NSLog(@"%@--%s--%@", [self class], __func__, @"start tvtune------");
        // 调幅开始
        NSInteger ret = 0;
        if(![[DeviceInterface shareInstance] sft_tvtune_start:sysmode retcode:&ret]) {
            NSLog(@"%@--%s---------error: sft_tvtune_start", [self class], __func__);
            [self fireBlock:failblock param1:[NSString stringWithFormat:@"%@ : %ld", NSLocalizedString(@"fail to start tvtune", nil), ret]];
            return NO;
        }
    }
    
    // 成功并保存制式
    self.preSysmode = sysmode;
    return YES;
}

- (BOOL)initDeviceAndStartMode:(DTV_Sysmode)sysmode fail:(FailBlock)failblock {
    NSLog(@"%@--%s--%@", [self class], __func__, @"------开始初始化");
    
    if (!self.is_initialized) {
        if (!(self.is_initialized = [self initDeviceAndOpenTune:failblock])) {
            return NO;
        }
    }
    
    if (self.preSysmode == DTV_Sysmode_MAX || self.preSysmode != sysmode) {
        if (![self startDtvmode:sysmode fail:failblock]) {
            self.preSysmode = DTV_Sysmode_MAX;
            return NO;
        }
        else {
            self.preSysmode = sysmode;
            return YES;
        }
    }
    
    return YES;
}

#pragma mark - New
// start dtvmode
- (BOOL)startDtvmode:(DTV_Sysmode)sysmode progress:(ProgressBlock)progressBlock fail:(FailBlock)failblock {
    
    //检测设备端是否支持当前的 dtv mode
    NSLog(@"%@--%s--%@", [self class], __func__, @"check supported dtvmode------");
    if(![[DeviceInterface shareInstance] sft_is_supported_dtvmode:sysmode]) {
        NSLog(@"device do not support for this dtv system type:%d\n", sysmode);
        [self fireBlock:failblock param1:NSLocalizedString(@"The system mode is not supported", nil)];
        return NO;
    }
    
    // 查看tvtune open状态
    BOOL b_tune_start_state = [[DeviceInterface shareInstance] sft_tvtune_get_tune_start_state];
    if (!b_tune_start_state) {
        NSLog(@"%@--%s--%@", [self class], __func__, @"start tvtune------");
        // 调幅开始
        NSInteger ret = 0;
        if(![[DeviceInterface shareInstance] sft_tvtune_start:sysmode retcode:&ret]) {
            NSLog(@"%@--%s---------error: sft_tvtune_start", [self class], __func__);
            [self fireBlock:failblock param1:[NSString stringWithFormat:@"%@ : %ld", NSLocalizedString(@"fail to start tvtune", nil), ret]];
            return NO;
        }
    }
    
    // 成功并保存制式
    self.preSysmode = sysmode;
    return YES;
}

- (BOOL)initDeviceAndStartMode:(DTV_Sysmode)sysmode progress:(ProgressBlock)progressBlock fail:(FailBlock)failblock {
    NSLog(@"%@--%s--%@", [self class], __func__, @"------开始初始化");
    
    if (!self.is_initialized) {
        [self fireBlock:progressBlock param1:0.0 param2:NSLocalizedString(@"open tv tune ...", nil)];
        if (!(self.is_initialized = [self initDeviceAndOpenTune:failblock])) {
            return NO;
        }
    }
    
    if (self.preSysmode == DTV_Sysmode_MAX || self.preSysmode != sysmode) {
        [self fireBlock:progressBlock param1:0.0 param2:NSLocalizedString(@"start tv tune ...", nil)];
        if (![self startDtvmode:sysmode fail:failblock]) {
            self.preSysmode = DTV_Sysmode_MAX;
            return NO;
        }
        else {
            self.preSysmode = sysmode;
            return YES;
        }
    }
    
    return YES;
}

#pragma mark Scan
- (void)scanWithSysModels:(NSArray *)models progress:(ProgressBlock)progressBlock callback:(ScanCompleteBlock)completeblock fail:(FailBlock)failblock {
    /* FIXME: 判断之前的扫描任务是否停止, 没停止则进行停止 */
    [self.control_queue addOperationWithBlock:^{
        /* FIXME: 扫描前先初始化 [self initDeviceAndStartMode:model.sys fail:failblock]; */
        while (self.queue.operations.count) {
            NSLog(@"%@--%s--%@ : %d", [self class], __func__, @"等待...", (int)self.queue.operations.count);
            usleep(10000);
        }
        self.is_stop_scan = NO;
        
        
        // 当前进度
        __weak typeof(self) weakSelf = self;
        self.scanned_program_count = 0;
        __block double curProgress = 0.0;
        __block double preProgress = 0.0;       // 已完成的若干频段频点总和占总频点数的比例
        
        weakSelf.tempProgTable = nil;
        
        // 从多个频段中统计要扫描的频点数
        NSInteger sum = 0;
        for (SysModel *model in models) {
            sum += model.sumFreqs;
        }
        
        /* FIXME: 扫描全部model才是一个扫描任务, 在这里加入队列 */
        for (SysModel *model in models) {
            [self fireBlock:progressBlock param1:0.0 param2:nil];
            
            // 扫描
            [self scanWithSysModel:model progress:^(double progress, NSString *info) {
                
                // 计算总进度
                if (1.0 == progress) // 完成一个频段的时候, 计算当前已完成扫描的频段频点总和占比
                    curProgress = preProgress += model.sumFreqs / (double)sum;
                else // 某个频段进行时
                    curProgress = preProgress + progress * ( model.sumFreqs / (double)sum );
                
                // 进度回调
                if (progressBlock)
                    progressBlock( curProgress, info );
                
                NSLog(@"%@--%s--curProgress: %f preProgress: %f", [weakSelf class], __func__, curProgress, preProgress);
                
            } callback:^(id table, id param) {
                if (1.0 == curProgress) { // 完成全部频段的扫描
                    progressBlock( curProgress, NSLocalizedString(@"completed", nil) );
                    [self stopScan];
                }
                
                if (table) {
                    if (!weakSelf.tempProgTable) weakSelf.tempProgTable = table;
                    else {
                        NSArray *programs = param;
                        for (Program *program in programs) {
                            program.table = weakSelf.tempProgTable;
                        }
                        
                        [weakSelf.tempProgTable.programs addObjectsFromArray:param];
                        [weakSelf.tempProgTable.freqPrograms addEntriesFromDictionary:((ProgramTable *)table).freqPrograms];
                    }
                    
                    if (completeblock) {
                        completeblock(weakSelf.tempProgTable, weakSelf.tempProgTable.programs);
                    }
                    
                    BOOL success = [NSKeyedArchiver archiveRootObject:weakSelf.tempProgTable toFile:[SandBoxUtil scanProgramTableArchiverPath]];
                    NSLog(@"--%s--序列化 : %@", __func__, success ? @"YES" : @"NO");
                }
            } fail:^(NSString *errorInfo) {
                
                [weakSelf stopScan];
                
                if (failblock) {
                    failblock(errorInfo);
                }
                
            }];
        }
    }];
}

- (void)scanWithFrequency:(NSInteger)frequency mode:(DTV_Sysmode)mode bandwidth:(int)bandwidth callback:(ScanCompleteBlock)callback fail:(FailBlock)failblock {

    __weak typeof(self) weakSelf = self;
    __block BOOL finished_frequency_scan = NO;
    BOOL scanSuccess = [[DeviceInterface shareInstance] sft_scan:(unsigned int)frequency mode:mode bandwidth:bandwidth completeBlock:^(ProgramTable *table, id param) {
        
        if (param) {
            
            NSArray *programs = param;
            // 增加序列
            for (int i = 0; i < programs.count; i++) {
                Video *video = programs[i];
                video.title = [NSString stringWithFormat:@"%02d %@", (int)self.scanned_program_count + i + 1, video.title];
                ((Program *)video).bandwidth = bandwidth;
            }
            weakSelf.scanned_program_count += programs.count;
            NSLog(@"%@--%s--scan program: %@: %ld", [self class], __func__, @"成功扫描节目", frequency);

        }
        if (callback) callback(table, param);
        /* FIXME: 当停止扫描时, 此处回调已结束, 则不需要发送信号 */
//        dispatch_semaphore_signal(self.semaphore);
        finished_frequency_scan = YES;
    }];

//    dispatch_semaphore_wait(self.semaphore, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC));
    int timeout = 20 * NSEC_PER_MSEC;
    while (!self.is_stop_scan && !finished_frequency_scan && timeout > 0 ) {
        timeout = timeout - 200000;
        usleep(200000);
    }
    
    if (scanSuccess) {
        NSLog(@"%@--%s--scan program: %@ frequency: %ld", [self class], __func__, @"成功发送扫描命令", frequency);
    }
    else {
        NSLog(@"%@--%s--scan program: %@ frequency: %ld", [self class], __func__, @"失败发送扫描命令", frequency);
    }
}

/**
 扫描一个频段

 @param model 记录频段信息
 @param progressBlock 当前频段扫描进度
 @param callback 扫描到节目返回
 @param failblock 失败回调
 */
- (void)scanWithSysModel:(SysModel *)model progress:(ProgressBlock)progressBlock callback:(ScanCompleteBlock)callback fail:(FailBlock)failblock {
#if DvbpsiScanProgram
    [self new_scanWithSysModel:model progress:progressBlock callback:callback fail:failblock];
    return;
#endif
    
    BOOL initRet = [self initDeviceAndStartMode:model.sys fail:failblock];
    if (!initRet) return;
    
    NSInteger start_freq = model.minFreq, end_freq = model.maxFreq, step_freq = model.stepFreq, center_freq;
    NSLog(@"%@--%s--scan program: %@频段扫描 start:%d end:%d", [self class], __func__, self.is_stop_scan ? @"停止" : @"开始", (int)start_freq, (int)end_freq);
    
    // 扫描
    for (center_freq = start_freq; center_freq <= end_freq; center_freq += step_freq) {
        
        __weak typeof(self) weakSelf = self;
        [self.queue addOperationWithBlock:^{
#if TestPauseScan
            while (self.is_pause_scan) {
                usleep(10000);
            }
#endif
            
            // 设置当前频点步进数
            NSInteger step = (center_freq - start_freq) / step_freq + 1;
            [self fireBlock:progressBlock param1:step / (double)model.sumFreqs param2:[NSString stringWithFormat:@"scan frequency:%d", (int)center_freq]];
            NSLog(@"%@--%s--scan program: 开始扫描频点: %d ", [self class], __func__, (int)center_freq);
            
            [weakSelf scanWithFrequency:center_freq mode:model.sys bandwidth:(int)model.stepFreq callback:callback fail:failblock];
        }];
    }
}

- (void)new_scanWithSysModel:(SysModel *)model progress:(ProgressBlock)progressBlock callback:(ScanCompleteBlock)completeblock fail:(FailBlock)failblock {
    
    self.completeBlock = completeblock;
    
    [self.queue addOperationWithBlock:^(void) {
        
        // 阻止下一个频段进行扫描
        if (self.is_stop_scan) return;
        
        self.is_stop_scan = NO;
        is_invoked_callback = YES;
        
        BOOL initRet = [self initDeviceAndStartMode:model.sys fail:failblock];
        if (!initRet) return;
        
        [self fireBlock:progressBlock param1:0.0 param2:nil];
        
        NSInteger start_freq = model.minFreq, end_freq = model.maxFreq, step_freq = model.stepFreq, center_freq;
        NSLog(@"%@--%s--%@频段扫描 start:%d end:%d ", [self class], __func__, self.is_stop_scan ? @"开始" : @"停止", (int)start_freq, (int)end_freq);
        
        // 扫描
        for(center_freq = start_freq; center_freq <= end_freq; center_freq += step_freq) {
            
            // 等待上次扫描完成
            while (!self.is_stop_scan && !is_invoked_callback)
                usleep(5000);
            if (self.is_stop_scan) break;
            
            is_invoked_callback = NO;
            
#if TestPauseScan
            while (self.is_pause_scan) {
                usleep(10000);
            }
#endif
            
            // 设置当前频点步进数
            NSInteger step = (center_freq - start_freq) / step_freq + 1;
            [self fireBlock:progressBlock param1:step / (double)model.sumFreqs param2:[NSString stringWithFormat:@"scan frequency:%ld kHz", (long)center_freq]];
            
            
            BOOL rSuccess = [[DeviceInterface shareInstance] sft_tvtune_regist_data_callback:^(void *buf, unsigned int bufsize) {
                stream_entry(buf, bufsize);
            } bufsize:streamBufferSize];
            
            if (!rSuccess) {
                is_invoked_callback = YES;
                continue;
            }
            
            // block
            NSMutableArray *pids = [NSMutableArray array];
            [pids addObject:@(0x1FFF)];
            
            BOOL resetSuccess = [[DeviceInterface shareInstance] sft_tvtune_set_channel:(int)center_freq sysmode:model.sys bandwidth:(int)model.stepFreq];
            if (!resetSuccess) {
                is_invoked_callback = YES;
                
                NSLog(@"%@--%s--%@", [self class], __func__, @"error: sft_tvtune_set_channel");
                [[DeviceInterface shareInstance] sft_tvtune_cancel_pidservice];
                continue;
            }
            
            BOOL selectSuccess = [[DeviceInterface shareInstance] sft_tvtune_select_pidserviceWithPids:pids block:YES];
            if (selectSuccess) {
                int ret = scan_program(model.sys, (int)center_freq, scan_program_complete, (__bridge void *)(self));
                //                int eit_tid[] = {0x4E, 0x50};
                //                int ret = scan_program_with_epg(model.sys, (int)center_freq, scan_complete, scan_eits_complete, eit_tid, (sizeof(eit_tid) / sizeof(int)), (__bridge void *)(self));
                if (ret != 0) is_invoked_callback = YES;
            }
            else {
                is_invoked_callback = YES;
            }
            
            [[DeviceInterface shareInstance] sft_tvtune_unregist_data_callback];
        }
        
    }];
    
}

- (void)new_stopScan {
    
    NSLog(@"%@--%s--%@", [self class], __func__, @"停止扫描");
    
    if(self.tempProgTable) self.programTable = self.tempProgTable; // 停止扫描时保存当前扫描结果
    self.scanned_program_count = 0;
    [self.queue cancelAllOperations];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
        NSLog(@"%@--%s--%@", [self class], __func__, [NSThread currentThread]);
        self.is_stop_scan = YES;
        is_invoked_callback = YES;
        
        /* FIXME: 此处的意义 ???? */
        [[DeviceInterface shareInstance] stop_scan_epg];
        
        // 设置初始化
        [self.queue addOperationWithBlock:^(void) {
            self.is_stop_scan = NO;
            is_invoked_callback = NO;
        }];
    });
}

- (void)stopScan {
#if DvbpsiScanProgram
    [self new_stopScan];
    return;
#endif
    
    if (self.tempProgTable) self.programTable = self.tempProgTable; // 停止扫描时保存当前扫描结果
    
    [self.control_queue cancelAllOperations];
    [self.control_queue addOperationWithBlock:^{
        NSLog(@"%@--%s--player release issue : %@", [self class], __func__, @"停止扫描");
        
        self.is_stop_scan = YES;
        BOOL suceess = [[DeviceInterface shareInstance] sft_stop_scan];
        NSLog(@"%@--%s--已经停止扫描? : %@", [self class], __func__, suceess ? @"YES" : @"NO");

//        dispatch_semaphore_signal(self.semaphore);
//        self.semaphore = dispatch_semaphore_create(0);
        
#if TestPauseScan
        self.is_pause_scan = NO;
#endif
        /* FIXME: 扫描过程中扫描的节目直接点击进入播放, 没来得及 */
//        if (self.tempProgTable) self.programTable = self.tempProgTable; // 停止扫描时保存当前扫描结果
        self.scanned_program_count = 0;
        NSLog(@"%@--%s--%@ : %d", [self class], __func__, @"取消任务数量", (int)self.queue.operations.count);
        [self.queue cancelAllOperations];
        
    }];
}

- (void)pauseScan:(BOOL)isPaused {
#if TestPauseScan
    self.is_pause_scan = isPaused;
#endif
}

/**
 * dvbpsi库扫描回调
 */
void scan_program_complete(scan_state_t *state, void *p_data) {
    
    if (!state) return;
    ScanChannel *self = (__bridge ScanChannel *)p_data;
    
    if (state->scan_type == (scan_type_program | scan_type_eit)) {
        BOOL is_stop_scan_epg = NO;
        
        if (state->found == 0) {
            NSMutableArray *pids = [NSMutableArray array];
            [pids addObject:@(0x0012)];
            
            BOOL selectSuccess = [[DeviceInterface shareInstance] sft_tvtune_select_pidserviceWithPids:pids block:NO];
            NSLog(@"%@--%s--scan epg sft_tvtune_select_pidserviceWithPids : %@", [self class], __func__, selectSuccess ? @"YES" : @"NO");
            is_stop_scan_epg = !selectSuccess;
        }
        else is_stop_scan_epg = YES;
        
        if (is_stop_scan_epg) {     // select pids 失败的话停止扫描epg, 后显示节目
            [[DeviceInterface shareInstance] stop_scan_epg];
            
            is_invoked_callback = YES;
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                self.completeBlock(self.programTable, self.programTable.programs);
            });
            
            [[DeviceInterface shareInstance] sft_tvtune_unregist_data_callback];
        }
        //    else return;
    }
    
    if ((state->scan_type & scan_type_program)) {
        
        int frequency = state->frequency;
        int dtvmode = state->dtvmode;
        
        // hash 值相同则为同一次扫描
        
        ProgramTable *proTable;
        if (!self.scanned_program_count) {
            proTable = [[ProgramTable alloc] init];
            self.programTable = proTable;
        }
        else {
            proTable = self.programTable;
        }
        proTable.sys = dtvmode;
        //    proTable.frequency = frequency;
        
        NSMutableArray *all_programs = [NSMutableArray array];
        NSMutableArray *programs = [NSMutableArray array];

        ts_pmt_t *tmp_pmt = state->p_stream->pmts.first_pmt;
        while (tmp_pmt) {
            if (tmp_pmt->i_number == 0) {
                tmp_pmt = tmp_pmt->next;
                continue;
            }
            
            int name_length = tmp_pmt->i_name_length;
            char *name = (char *)tmp_pmt->c_program_name;
            
            NSString *program_name;
            if (name != NULL) {
                convert_textcode(&name, &name_length);
                
                program_name = [[NSString alloc] initWithData:[NSData dataWithBytes:name length:name_length] encoding:NSUTF8StringEncoding];
                //        NSString *program_name = [NSString stringWithCString:(char *)tmp_pmt->c_program_name encoding:NSUTF8StringEncoding];
            }
            
            // 创建一个节目
            Program *pro = [Program new];
            pro.frequency = frequency;
            pro.sysMode = dtvmode;
            
            // 取出名字
            pro.title = program_name;
            pro.pmtID = tmp_pmt->pid_pmt->i_pid;
            pro.number = tmp_pmt->i_number;
            //        pro.pcr_pid = tmp_pmt->pid_pcr->i_pid;
            pro.isAudioSource = YES;
            
            
            // 保存ID
            NSMutableArray *arrayID = [NSMutableArray array];
            NSMutableArray *videoIDs = [NSMutableArray array];
            NSMutableArray *audioIDs = [NSMutableArray array];
            NSMutableArray *extraIDs = [NSMutableArray array];
            descriptor_es_t *es = tmp_pmt->pmt_es_descriptor;
            while (es) {
                
                if ([[DeviceInterface shareInstance].esStreamTypes containsObject:@(es->i_type)]) {
                    [arrayID addObject:@(es->i_pid)];
                    
                    // 是否有视频id
                    if ([[DeviceInterface shareInstance].esVideoStreamTypes containsObject:@(es->i_type)]) {
                        pro.isAudioSource = NO;
                        [videoIDs addObject:@(es->i_pid)];
                    }
                    else
                        [audioIDs addObject:@(es->i_pid)];
                }
                else {
                    [extraIDs addObject:@(es->i_pid)];
                }
                es = es->next_sibling;
            }
            
            pro.arrayID = arrayID;
            pro.videoIDs = videoIDs;
            pro.audioIDs = audioIDs;
            pro.extraIDs = extraIDs;
            pro.table = proTable;
            if (arrayID.count) [programs addObject:pro];
            [all_programs addObject:pro];
            
            tmp_pmt = tmp_pmt->next;
        }
        
        [proTable.freqPrograms setObject:all_programs forKey:@(frequency)];
        [proTable.programs addObjectsFromArray:programs];
        
        
        if (proTable) {
            
            // 增加序列
            for (int i = 0; i < programs.count; i++) {
                Video *video = programs[i];
                video.title = [NSString stringWithFormat:@"%02d %@", (int)self.scanned_program_count + i + 1, video.title];
            }
            
            self.scanned_program_count += programs.count;
            
            BOOL success = [NSKeyedArchiver archiveRootObject:proTable toFile:[SandBoxUtil scanProgramTableArchiverPath]];
            NSLog(@"--%s--序列化 : %@", __func__, success ? @"YES" : @"NO");
        }
        
        if (state->scan_type == scan_type_program) {
            is_invoked_callback = YES;
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                self.completeBlock(proTable, programs);
            });
        }
    }
}

#pragma mark Filter
- (void)filterStream:(Program *)program block:(BOOL)block bufferCallback:(BufferCallbackBlock)callback complete:(CompleteBlock)completeblock {
    NSLog(@"%@--%s--%@", [self class], __func__, @"----------提交拉流任务");
    [self.control_queue addOperationWithBlock:^{
    
        int center_freq = (int)program.frequency;
        
        __weak BufferCallbackBlock temp_w_callback = callback;
        
        [self.queue addOperationWithBlock:^(void) {
            
            NSLog(@"%@--%s--player release issue : play_task %@", [self class], __func__, @"开始拉流任务");

            __strong BufferCallbackBlock temp_s_callback = temp_w_callback;
            
            // 在callback被清空的时候, 退出select pids service
            BOOL is_need_exit = (nil == temp_s_callback);
            NSLog(@"%@--%s--is_need_exit : %@", [self class], __func__, is_need_exit ? @"YES" : @"NO");
            if (is_need_exit) return ;
            
            BOOL initRet = [self initDeviceAndStartMode:program.sysMode fail:^(NSString *errorInfo) {
                [self fireCompleteBlock:completeblock param1:NO param2:errorInfo];
            }];
            if (!initRet) return;
            
            // 注册接收数据
            {
                BOOL rSuccess = NO;
                int i = 0;
                while (!rSuccess && i < 2) {
                    if (is_need_exit) return ;
                    NSLog(@"%@--%s--%@", [self class], __func__, @"regist data callback");
                    rSuccess = [[DeviceInterface shareInstance] sft_tvtune_regist_data_callback:callback bufsize:streamBufferSize];
                    i++;
                }
                if (!rSuccess) {
                    [self fireCompleteBlock:completeblock param1:NO param2:NSLocalizedString(@"tvtune fail to register data callback", nil)];
                    return ;
                }
            }
            
            // 筛选PIDs
            NSMutableArray *pids = [NSMutableArray array];
            
            // block
            ProgramTable *proTable = program.table;
            NSLog(@"%@--%s--ProgramTable 为空 : %@", [self class], __func__, proTable == nil ? @"YES" : @"NO");
            NSArray *programs = [proTable.freqPrograms objectForKey:@(program.frequency)];
            if (block) {
                [pids addObject:@(0x1FFF)];
                
                NSMutableArray *extraPids = [NSMutableArray array];
                NSMutableArray *videoIDs = [NSMutableArray array];
                NSMutableArray *audioIDs = [NSMutableArray array];
                for (Program *p in programs) {
                    if ([program isEqual:p]) continue;
                    
    //                [pids addObjectsFromArray:p.arrayID];
                    
                    [pids addObject:@(p.pmtID)];   // 优先过滤其他节目的pmt的pid
                    
                    [videoIDs addObjectsFromArray:p.videoIDs];
                    [audioIDs addObjectsFromArray:p.audioIDs];
                    [extraPids addObjectsFromArray:p.extraIDs];
                }
                [pids addObjectsFromArray:videoIDs];
                [pids addObjectsFromArray:audioIDs];
                [pids addObjectsFromArray:extraPids];
                
                [pids removeObjectsInArray:program.extraIDs];
                [pids removeObjectsInArray:program.arrayID];
            }
            // not block
            else {
                [pids addObject:@0x0000]; // PAT
                [pids addObject:@0x0012]; // EIT
                [pids addObject:@0x0014]; // TOT/TDT
                [pids addObject:@(program.pmtID)]; //PMT
                [pids addObject:@(program.pcr_pid)];
                
                [pids addObjectsFromArray:program.arrayID];
            }
            
            
            {
            DeviceStatus status = DeviceStatusOtherError;
            int i = 0;
            while (status != DeviceStatusNormal && i < 2) {
                
                if (is_need_exit) {
                    NSLog(@"%@--%s--%@", [self class], __func__, @"----------------is_need_exit");
                    return ;
                }
                NSLog(@"%@--%s--%@", [self class], __func__, @"tvtune select pidservice resetchannel");
                status = [[DeviceInterface shareInstance] sft_tvtune_select_pidservice_resetchannel:center_freq mode:program.sysMode bandwidth:(int)program.bandwidth pids:pids block:block];
                i++;
            }
            if (status == DeviceStatusNormal) {
                NSLog(@"%@--%s--%@", [self class], __func__, @"success: sft_tvtune_select_pidservice");
                
                NSString *info = nil;
    #if TestFloatBall
                NSMutableString *pidStr = [NSMutableString stringWithString:block ? @"block: " : @"!block: "];
                for (NSNumber *pid in pids) {
                    [pidStr appendFormat:@"%@,", pid];
                }
                info = pidStr;
    #endif
                [self fireCompleteBlock:completeblock param1:YES param2:info];
                
            }
            else {
                NSLog(@"%@--%s--%@", [self class], __func__, @"error: sft_tvtune_select_pidservice");
                [[DeviceInterface shareInstance] sft_tvtune_cancel_pidservice];
                
                NSString *notice = NSLocalizedString(@"tvtune fail to select pidservice", nil);
                if (status == DeviceStatusTimeout35) notice = NSLocalizedString(@"network is poor", nil);
                else notice = [NSString stringWithFormat:@"%@ : %d", notice, status];
                [self fireCompleteBlock:completeblock param1:NO param2:notice];
                return;
            }
            
            }
            
        }];
    }];
}

- (void)stopFilterStream {
    
    NSLog(@"%@--%s--player release issue : play_task %@ : %lu", [self class], __func__, @"停止拉流", (unsigned long)self.queue.operationCount);
    [self.queue cancelAllOperations];
    
    [self.queue addOperationWithBlock:^(void) {
        NSLog(@"%@--%s--player release issue : play_task %@", [self class], __func__, @"停止拉流任务");

        [[DeviceInterface shareInstance] stop_scan_epg];
        
        {
        BOOL resetSuccess = NO;
        int i = 0;
        while (!resetSuccess && i < 2) {
            NSLog(@"%@--%s--%@", [self class], __func__, @"sft_tvtune_unregist_data_callback");
            resetSuccess = [[DeviceInterface shareInstance] sft_tvtune_unregist_data_callback];
            i++;
        }
        NSLog(@"%@--%s--sft_tvtune_unregist_data_callback : %@", [self class], __func__, resetSuccess ? @"YES" : @"NO");
        }
        
        {
        BOOL resetSuccess = NO;
        int i = 0;
        while (!resetSuccess && i < 2) {
            NSLog(@"%@--%s--%@", [self class], __func__, @"sft_tvtune_cancel_pidservice");
            resetSuccess = [[DeviceInterface shareInstance] sft_tvtune_cancel_pidservice];
            i++;
        }
        NSLog(@"%@--%s--sft_tvtune_cancel_pidservice : %@", [self class], __func__, resetSuccess ? @"YES" : @"NO");
        }
        
    }];
}

- (void)fireBlock:(ProgressBlock)block param1:(double)param1 param2:(id)param2 {
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        if (block) block(param1, param2);
    });
}

- (void)fireCompleteBlock:(CompleteBlock)block param1:(BOOL)param1 param2:(id)param2 {
//    dispatch_async(dispatch_get_main_queue(), ^(void) {
        if (block) block(param1, param2);
//    });
}

- (void)fireBlock:(FailBlock)block param1:(id)param1 {
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        if (block) block(param1);
    });
}

#pragma mark -
- (void)dowithAppWillTerminate {
    
    [[DeviceInterface shareInstance] sft_tvtune_unregist_data_callback];
    
    [[DeviceInterface shareInstance] sft_tvtune_delete_channel];
    
    [[DeviceInterface shareInstance] sft_tvtune_cancel_pidservice];
    
    [[DeviceInterface shareInstance] sft_tvtune_stop];
    
    [[DeviceInterface shareInstance] sft_tvtune_close];
    
    NSLog(@"%@--%s--%@", [self class], __func__, @"app 被 kill");
}


@end
