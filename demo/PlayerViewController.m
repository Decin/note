
//  PlayerViewController.m
//  WiFiDisk
//
//  Created by NS on 2017/8/21.
//  Copyright © 2017年 Decin. All rights reserved.
//

#import "PlayerViewController.h"

#import <MediaPlayer/MediaPlayer.h>
#import "SQVideoConst.h"
#import "SQVideoControlView.h"
//#import <MobileVLCKit/MobileVLCKit.h>
#import "MobileVLCKit.h"

#import "VideoList.h"
#import "VideoCell.h"

#import "ScanChannel.h"

#import "ns_variable_queue.h"

#import "ScanViewController.h"

#import "DeviceInterface.h"
#import "SandBoxUtil.h"
#import "ProgramTable.h"

#import "DataUtil.h"
#import "PlayManager.h"

#if TestFloatBall
#import "WMAssistantBall.h"
#endif

#import "EPGPublic.h"
#import "PlayerLockView.h"


@interface PlayerViewController ()<VLCMediaPlayerDelegate, UIGestureRecognizerDelegate, SQVideoControlViewDelegate, UICollectionViewDelegateFlowLayout, UICollectionViewDelegate>

//////////////////////////////////////////////     Video UI    /////////////////////////////////////////////////////////
@property (strong, nonatomic) UIView *videoContainerView;               ///< 视频相关的视图容器

@property (strong, nonatomic) SQVideoControlView *controlView;          ///< 播放控制视图, videoContainerView subview, 横竖屏下跟随父类变化

@property (strong, nonatomic) PlayerLockView *lockView;                 ///< 锁屏, videoContainerView's subview
@property (assign, nonatomic) BOOL isLockingScreen;                     ///< 锁屏状态

@property (strong, nonatomic) UIView *drawableView;                     ///< 视频render, videoContainerView subview, 横竖屏下跟随父类变化
@property (strong, nonatomic) UIImageView *audioSourceNoticeView;       ///< 音频提示View, drawableView subview

//////////////////////////////////////////////     Program List     /////////////////////////////////////////////////////////
@property (strong, nonatomic) UIView *listContainerView;                ///< controlView subview, index = top
@property (strong, nonatomic) UIView *tabarMenuView;                    ///< 全屏下的右侧菜单, 竖屏下的列表菜单
@property (strong, nonatomic) NSArray<UIButton *> *tabarBtns;
@property (strong, nonatomic) VideoList *videoList;


//////////////////////////////////////////////     EPG     /////////////////////////////////////////////////////////
@property (strong, nonatomic) UIView *epgContainerView;                 ///< controlView subview, index = top
@property (strong, nonatomic) EPGView *epgView;
@property (strong, nonatomic) UIView *leftMenuView;                     ///< 左侧菜单
@property (strong, nonatomic) NSArray<UIButton *> *leftBtns;            ///< 左侧按钮


//////////////////////////////////////////////     Record     /////////////////////////////////////////////////////////
@property (strong, nonatomic) RecordingView *recordingView;             ///< 录屏, videoContainerView's subview
@property (assign, nonatomic) BOOL isRecording;                         ///< 录屏状态


//////////////////////////////////////////////     Data     /////////////////////////////////////////////////////////
@property (nonatomic, strong) VLCMediaPlayer *player;
@property (strong, nonatomic) VLCMedia *currentMedia;
@property (weak,   nonatomic) Video *currentVideo;
@property (strong, nonatomic) NSArray *videoAspectRatios;
@property (copy  , nonatomic) NSString *currentVideoRatio;

@property (weak  , nonatomic) NSTimer *signalTimer;

@property (assign, nonatomic) double buffering;                         /// vlc buffering quantity

@property (strong, nonatomic) CallbackBlock bufferCallback;

#if TestFloatBall
@property (strong, nonatomic) WMAssistantBall *assistantBall;
#endif

@property (assign, nonatomic) BOOL isAppActive;                         ///< 进入前台和后台tag
@property (nonatomic, assign) BOOL isFullscreenModel;

@property (strong, nonatomic) dispatch_queue_t eit_queue;
@property (strong, nonatomic) dispatch_queue_t eit_complete_queue;


//////////////////////////////////////////////    Did not use     /////////////////////////////////////////////////////////
@property (strong, nonatomic) NSCondition *conlock;

@property (assign, nonatomic) CGRect originFrame;

@property (strong, nonatomic) dispatch_group_t play_task_group;
@property (strong, nonatomic) dispatch_queue_t play_task_queue;
@property (strong, nonatomic) dispatch_semaphore_t semaphore;

@property (strong, nonatomic) NSMutableArray *group_blocks;                     ///< 需要保证add, remove线程安全

#if UseVLCListPlayer
@property (nonatomic, strong) VLCMediaListPlayer *listPlayer;                   ///< 列表播放器
@property (strong, nonatomic) VLCMediaList *imemMediaList;
@property (strong, nonatomic) VLCMediaList *recordMediaList;

@property (strong, nonatomic) NSMutableArray<VLCMedia *> *imemMedias;            ///< 当前播放的媒体数组

@property (strong, nonatomic) NSArray *records;
@property (strong, nonatomic) NSArray *recordMedias;

@property (strong, nonatomic) NSOperationQueue *playTaskQueue;
#else

#endif
@end

@implementation PlayerViewController

#pragma mark - Life Cycle
- (instancetype)init {
    if (self = [super init]) {
        
        _is_quit_page = false;
        self.isAppActive = YES;
        
        self.play_task_queue = dispatch_queue_create("play_task_queue", DISPATCH_QUEUE_SERIAL);
        self.play_task_group = dispatch_group_create();
        self.semaphore = dispatch_semaphore_create(0);
        self.group_blocks = [NSMutableArray array];
        #if UseVLCListPlayer
        self.playTaskQueue = [[NSOperationQueue alloc] init];
        self.playTaskQueue.name = @"PlayTaskQueue";
        #else
        _is_imem_closed = true;
        _is_need_stop = false;
        #endif
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.eit_queue = dispatch_queue_create("eit_queue", DISPATCH_QUEUE_SERIAL);
    self.eit_complete_queue = dispatch_queue_create("eit_complete_queue", DISPATCH_QUEUE_SERIAL);

    // 视频播放器初始化
    [self setupView];
    [self setupControlView];
    [self setupNotification];

    [self observeDataIsNullOrNot:YES];
    
    
    // get data and refresh layout
    if ([self.currentVideo isKindOfClass:[Program class]]) {
        [self selectShowAndLoadData:0];
    }
    else {
        [self selectShowAndLoadData:2];
    }
    self.videos = self.videoList.videos;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
}

- (void)updateViewConstraints {
    [super updateViewConstraints];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    self.navigationController.navigationBarHidden = YES;
//    [[UIApplication sharedApplication] setStatusBarHidden:YES];
    
    // reset property `is_initialized` when wifi disconnect
    [[NetworkUtil shareInstance] startMonitoringRepeat:YES showViewController:self changeBlock:^(BOOL isMatch, NSString *desc) {
        [ScanChannel shareInstance].is_initialized = NO;
    }];
    
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
//    [[UIApplication sharedApplication] setStatusBarHidden:NO];
    self.navigationController.navigationBarHidden = NO;

}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    [self.signalTimer fire];
    
#if TestFloatBall
    //测试网速, cpu等
    self.assistantBall = [[WMAssistantBall alloc] init];            // 一定要作为一个局部属性
#if AssistantBallReleaseVLCFirst
    self.assistantBall.addtionItems = @[@"block", @"release", @""];      // 额外加一些按钮
#else
    self.assistantBall.addtionItems = @[@"block", @"!release", @""];      // 额外加一些按钮
#endif // AssistantBallReleaseVLCFirst
    self.assistantBall.ballColor = [UIColor blueColor];             // 按钮颜色
    self.assistantBall.shapeColor = [UIColor redColor];             // 移动时的光圈颜色
    [self.assistantBall doWork];                                    // 很重要 一定要调用
    
    
    __weak typeof(self) weakSelf = self;
    //点击了某一个选项
    self.assistantBall.selectBlock = ^(NSString *title, UIButton *btnton) {
        NSLog(@"%@", title);
        if ([title isEqualToString:@"CPU"]) {
            [weakSelf.assistantBall makeChart:1 pCtrl:weakSelf];
        }
        else if ([title isEqualToString:@"内存"]) {
            [weakSelf.assistantBall makeChart:2 pCtrl:weakSelf];
        }
        else if ([title isEqualToString:@"下载"]) {
            [weakSelf.assistantBall makeChart:3 pCtrl:weakSelf];
        }
        else if ([title isEqualToString:@"上传"]) {
            [weakSelf.assistantBall makeChart:4 pCtrl:weakSelf];
        }
        else if ([title isEqualToString:@"!block"]) {
            weakSelf.assistantBall.addtionItems = @[@"block", weakSelf.assistantBall.addtionItems[1], @""];     //额外加一些按钮
            [weakSelf.assistantBall updateButtons];
        }
        else if ([title isEqualToString:@"block"]) {
            weakSelf.assistantBall.addtionItems = @[@"!block", weakSelf.assistantBall.addtionItems[1], @""];     //额外加一些按钮
            [weakSelf.assistantBall updateButtons];
        }
        else if ([title isEqualToString:@"release"]) {
            weakSelf.assistantBall.addtionItems = @[weakSelf.assistantBall.addtionItems[0], @"!release", @""];     //额外加一些按钮
            [weakSelf.assistantBall updateButtons];
        }
        else if ([title isEqualToString:@"!release"]) {
            weakSelf.assistantBall.addtionItems = @[weakSelf.assistantBall.addtionItems[0], @"release", @""];     //额外加一些按钮
            [weakSelf.assistantBall updateButtons];
        }
    };
#endif // TestFloatBall
    
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    
    [_signalTimer invalidate];
    _signalTimer = nil;
    
    [[NetworkUtil shareInstance] stopMonitoring];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    
    NSLog(@"%@--%s--%@", [self class], __func__, @"内存警告");
}

- (void)dealloc {
    
    [_player stop];
    _player = nil;
    
    
    _is_quit_page = true;   // 有可能由于循环应用问题导致下次进入控制器才释放, 在init后才会调用dealloc, 导致重新赋值
    if (bufQueue.abhead != NULL) empty_variable_queue(&bufQueue);
    _bufferCallback = nil;
    
    NSLog(@"%@--%s-- player release issue : %@", [self class], __func__, @"退出player控制器");
}


#pragma mark - Private Method
- (void)setupView {
    
    [self.view setBackgroundColor:[UIColor blackColor]];
    
    [self.view addSubview:self.videoContainerView];
    
    [self.videoContainerView addSubview:self.drawableView];
    [self.videoContainerView addSubview:self.controlView];
    //    [self.videoContainerView addSubview:self.listContainerView];  // depend on fullscreen state
    
    [self.drawableView addSubview:self.audioSourceNoticeView];
    
    [self.listContainerView addSubview:self.tabarMenuView];
    [self.listContainerView addSubview:self.videoList];
    [self.epgContainerView addSubview:self.leftMenuView];
    
    [self.audioSourceNoticeView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.width.height.mas_equalTo(130.0);
        make.center.equalTo(self.drawableView);
    }];
    
    for (UIButton *btn in self.tabarBtns)
        [self.tabarMenuView addSubview:btn];
    
    for (UIButton *btn in self.leftBtns)
        [self.leftMenuView addSubview:btn];
    
    [self.videoContainerView mas_makeConstraints:^(MASConstraintMaker *make) {
        //        make.edges.equalTo(self.view);
        make.left.right.top.equalTo(self.view);
        make.width.equalTo(self.videoContainerView.mas_height).multipliedBy(16.0 / 9.0);
    }];
    
    [self.drawableView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.videoContainerView);
    }];
    
    [self.controlView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.videoContainerView);
    }];
    
    self.isFullscreenModel = NO;
    
    [self initLandscapeOrPortrait:YES];
}

- (void)initLandscapeOrPortrait:(BOOL)isPortrait {
    __weak typeof(self) weakSelf = self;
    
    if (!isPortrait) {
        // show switchview
        self.controlView.switchView.hidden = NO;//![self.currentVideo isKindOfClass:[Program class]];
        self.controlView.titleLabel.hidden = !self.controlView.switchView.hidden;
        
        // show controlview and tabarMenu when screen is stretched
        self.controlView.beforeHideBlock = ^{
            [weakSelf animateHideTabarMenu];
        };
        self.controlView.beforeShowBlock = ^{
            [weakSelf animateShowTabarMenu];
        };
        [self.controlView animateShow];
        
        // add to self.view, to make constraint
        [self.controlView addSubview:self.listContainerView];
        [self.controlView addSubview:self.epgContainerView];
        self.epgContainerView.hidden = NO;
        self.listContainerView.hidden = NO;
        self.videoList.hidden = YES;
        self.epgView.hidden = YES;
        
        // videolist container
        [self.listContainerView mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.height.equalTo(self.controlView.mas_height).multipliedBy(0.4);
            make.height.mas_greaterThanOrEqualTo(90);
            make.width.mas_equalTo(50);
            make.right.equalTo(self.controlView);
            make.centerY.equalTo(self.controlView.mas_centerY);
        }];
        
        // tabarMenuView and subviews
        [self.tabarMenuView mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.height.equalTo(self.videoContainerView.mas_height).multipliedBy(0.4);
            make.height.mas_greaterThanOrEqualTo(90);
            make.width.mas_equalTo(50);
            make.right.equalTo(self.listContainerView);
            make.centerY.equalTo(self.listContainerView.mas_centerY);
        }];
        
        [self.tabarBtns[0] mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.top.left.right.equalTo(self.tabarMenuView);
        }];
        
        [self.tabarBtns[1] mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.left.right.equalTo(self.tabarMenuView);
            make.top.equalTo(self.tabarBtns[0].mas_bottom).mas_offset(1.0);
            
            make.width.equalTo(self.tabarBtns[0]);
            make.height.equalTo(self.tabarBtns[0]);
        }];
        
        [self.tabarBtns[2] mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(self.tabarBtns[1].mas_bottom).mas_offset(1.0);
            make.left.right.equalTo(self.tabarMenuView);
            make.bottom.equalTo(self.tabarMenuView);
            
            make.width.equalTo(self.tabarBtns[1]);
            make.height.equalTo(self.tabarBtns[1]);
        }];
        
        // videolist
        [self.videoList mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.width.equalTo(self.listContainerView).multipliedBy(0.38);
            make.top.bottom.equalTo(self.listContainerView);
            make.right.equalTo(self.tabarMenuView.mas_left);
        }];
        
        // EPG container
        [self.epgContainerView mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.height.equalTo(self.controlView.mas_height).multipliedBy(0.4);
            make.height.mas_greaterThanOrEqualTo(90);
            make.width.mas_equalTo(50);
            make.left.equalTo(self.controlView);
            make.centerY.equalTo(self.controlView.mas_centerY);
        }];
        
        // leftMenuView and subviews
        [self.leftMenuView mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.height.equalTo(self.videoContainerView.mas_height).multipliedBy(0.4);
            make.height.mas_greaterThanOrEqualTo(90);
            make.width.mas_equalTo(50);
            make.left.equalTo(self.epgContainerView);
            make.centerY.equalTo(self.epgContainerView.mas_centerY);
        }];
        
        [self.leftBtns[0] mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.top.left.right.equalTo(self.leftMenuView);
        }];
        
        [self.leftBtns[1] mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.left.right.equalTo(self.leftMenuView);
            make.top.equalTo(self.leftBtns[0].mas_bottom).mas_offset(1.0);
            
            make.width.equalTo(self.leftBtns[0]);
            make.height.equalTo(self.leftBtns[0]);
        }];
        
        [self.leftBtns[2] mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(self.leftBtns[1].mas_bottom).mas_offset(1.0);
            make.left.right.equalTo(self.leftMenuView);
            make.bottom.equalTo(self.leftMenuView);
            
            make.width.equalTo(self.leftBtns[1]);
            make.height.equalTo(self.leftBtns[1]);
        }];
        
    }
    else {
        // show switchview
        self.controlView.switchView.hidden = YES;
        self.controlView.titleLabel.hidden = NO;
        
        // clear block beacuse tabarMenuView will be displaying
        self.controlView.beforeHideBlock = nil;
        self.controlView.beforeShowBlock = nil;
        
        // show tabarMenuView as tabar when videoscreen is shrunk
        [self.controlView animateShow];
        [self cancelAutoFadeOutTabarMenu];
        
        // add to self.view, to make constraint
        [self.view addSubview:self.listContainerView];
        [self.epgContainerView removeFromSuperview];
        self.listContainerView.hidden = NO;
        self.videoList.hidden = NO;

        // videolist container
        [self.listContainerView mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(self.videoContainerView.mas_bottom).mas_offset(1.0);
            id des;
            if (@available(iOS 11.0, *)) des = self.view.mas_safeAreaLayoutGuide;
            else des = self.view;
            make.left.right.bottom.equalTo(des);
        }];
        
        // tabarMenuView and subviews
        [self.tabarMenuView mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.top.left.right.equalTo(self.listContainerView);
            make.height.mas_equalTo(40.0);
        }];
        
        [self.tabarBtns[0] mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.left.top.equalTo(_tabarMenuView);
            make.bottom.equalTo(_tabarMenuView).offset(-1.0);
        }];
        
        [self.tabarBtns[1] mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(self.tabarBtns[0]);
            make.bottom.equalTo(self.tabarBtns[0]).offset(-1.0);
            
            make.left.equalTo(self.tabarBtns[0].mas_right).mas_offset(1.0);
            
            make.width.equalTo(self.tabarBtns[0]);
            make.height.equalTo(self.tabarBtns[0]);
        }];
        
        [self.tabarBtns[2] mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.top.bottom.equalTo(self.tabarBtns[1]);
            make.bottom.equalTo(self.tabarBtns[1]).offset(-1.0);
            make.left.equalTo(self.tabarBtns[1].mas_right).mas_offset(1.0);
            make.right.equalTo(self.tabarMenuView.mas_right);
            
            make.width.equalTo(self.tabarBtns[1]);
            make.height.equalTo(self.tabarBtns[1]);
        }];
        
        // videolist
        [self.videoList mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(self.tabarMenuView.mas_bottom);
            make.left.bottom.right.equalTo(self.listContainerView);
        }];
    }
}

- (void)setupControlView {
    [self.controlView setShouldGesture:YES];
    
    //添加控制界面的监听方法
    [self.controlView.playButton addTarget:self action:@selector(playButtonClick) forControlEvents:UIControlEventTouchUpInside];
    [self.controlView.pauseButton addTarget:self action:@selector(pauseButtonClick) forControlEvents:UIControlEventTouchUpInside];
    [self.controlView.closeButton addTarget:self action:@selector(closeButtonClick) forControlEvents:UIControlEventTouchUpInside];
    [self.controlView.recordButton addTarget:self action:@selector(recordButtonClick:) forControlEvents:UIControlEventTouchUpInside];
    [self.controlView.scanButton addTarget:self action:@selector(scanButtonClick) forControlEvents:UIControlEventTouchUpInside];
    [self.controlView.favoriteButton addTarget:self action:@selector(favoriteButtonClick:) forControlEvents:UIControlEventTouchUpInside];
    [self.controlView.fullScreenButton addTarget:self action:@selector(fullScreenButtonClick) forControlEvents:UIControlEventTouchUpInside];
    [self.controlView.shrinkScreenButton addTarget:self action:@selector(shrinkScreenButtonClick) forControlEvents:UIControlEventTouchUpInside];
    
    [self.controlView.centerPlayButton addTarget:self action:@selector(playCurrentVideo) forControlEvents:UIControlEventTouchUpInside];
    
    [self.controlView.progressSlider addTarget:self action:@selector(progressClick) forControlEvents:UIControlEventTouchUpInside];
    //    [self.controlView.progressSlider addTarget:self action:@selector(progressChanged:) forControlEvents:UIControlEventValueChanged];
    [self.controlView.volumeSlider addTarget:self action:@selector(volumeChanged:) forControlEvents:UIControlEventValueChanged];
    
    [self.controlView.switchView.preVideoBtn addTarget:self action:@selector(preVideo:) forControlEvents:UIControlEventTouchUpInside];
    [self.controlView.switchView.nextVideoBtn addTarget:self action:@selector(nextVideo:) forControlEvents:UIControlEventTouchUpInside];
    
}

- (void)setupNotification {
    
    //开启和监听 设备旋转的通知（不开启的话，设备方向一直是UIInterfaceOrientationUnknown）
    //    if (![UIDevice currentDevice].generatesDeviceOrientationNotifications) {
    //    }
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    NSLog(@"%@--%s--是否生成通知 : %@", [self class], __func__, [UIDevice currentDevice].generatesDeviceOrientationNotifications ? @"YES" : @"NO");
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(orientationHandler)
                                                 name:UIDeviceOrientationDidChangeNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillEnterForeground)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
    
    //    UIApplicationDidBecomeActiveNotification
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}


#pragma mark - Notification Handler
/**
 *    屏幕旋转处理
 */
- (void)orientationHandler {
    
    // 竖屏
    if (UIDeviceOrientationIsPortrait([UIDevice currentDevice].orientation) && self.view.frame.size.width < self.view.frame.size.height) {
        
        if (self.isFullscreenModel) {
            self.isFullscreenModel = NO;
            
            // get data and refresh layout
            if ([self.currentVideo isKindOfClass:[Program class]]) {
                [self selectShowAndLoadData:0];
            }
            else {
                [self selectShowAndLoadData:2];
            }
        }
        NSLog(@"%@--%s--竖屏 %ld", [self class], __func__, [UIDevice currentDevice].orientation);
        
    }
    // 横屏
    else if (UIDeviceOrientationIsLandscape([UIDevice currentDevice].orientation) && self.view.frame.size.width >= self.view.frame.size.height) {
        
        if (!self.isFullscreenModel) {
            for (UIButton *btn in self.tabarBtns) {
                btn.selected = NO;
            }
            
            self.isFullscreenModel = YES;
        }
        NSLog(@"%@--%s--横屏 %ld", [self class], __func__, [UIDevice currentDevice].orientation);
    }
    
}

// 即将返回前台的处理
- (void)applicationWillEnterForeground {
    NSLog(@"%@--%s-- player release issue: %@", [self class], __func__, @"将进入前台");
    
    if ([self.currentVideo isKindOfClass:[Program class]]) {
        self.isAppActive = YES;
        
        NSLog(@"%@--%s-- player release issue %@", [self class], __func__, @"进入前台重新播放 _______________");
        [self switchVideo:self.currentVideo];
        
    }
    else {
        // 播放中回到前台 player: _cachedState = VLCMediaPlayerStatePaused  media: _state = VLCMediaStatePlaying
        // 停止后回到前台 player: _cachedState = VLCMediaPlayerStateStopped  media: _state = VLCMediaStateNothingSpecial
        if (self.player.state == VLCMediaPlayerStatePaused) [self play];
    }
    
}

- (void)applicationDidBecomeActive {
    NSLog(@"%@--%s- player release issue: -%@", [self class], __func__, @"进入前台");
}

// 即将进入后台的处理, 系统顶部下拉菜单, 以及底部上拉菜单
- (void)applicationWillResignActive {
    NSLog(@"%@--%s-- player release issue: %@", [self class], __func__, @"将进入后台");
    
    
}

- (void)applicationDidEnterBackground {
    NSLog(@"%@--%s-- player release issue: %@", [self class], __func__, @"进入后台");
    
    if ([self.currentVideo isKindOfClass:[Program class]])  {
        self.isAppActive = NO;
        empty_variable_queue(&bufQueue);
    }
    
    if (self.player.state == VLCMediaPlayerStatePlaying) [self pause];
}


#pragma mark -
////实现隐藏方法
- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationPortrait;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return self.isLockingScreen || self.isRecording ? UIInterfaceOrientationMaskLandscape : UIInterfaceOrientationMaskAllButUpsideDown;
}

- (BOOL)shouldAutorotate {
    return YES;
}


/**
 *    强制横屏
 *
 *    @param orientation 横屏方向
 */
- (void)forceChangeOrientation:(UIInterfaceOrientation)orientation
{
    int val = orientation;
    if ([[UIDevice currentDevice] respondsToSelector:@selector(setOrientation:)]) {
        SEL selector = NSSelectorFromString(@"setOrientation:");
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[UIDevice instanceMethodSignatureForSelector:selector]];
        [invocation setSelector:selector];
        [invocation setTarget:[UIDevice currentDevice]];
        [invocation setArgument:&val atIndex:2];
        [invocation invoke];
    }
}

#pragma mark - Get Data
- (void)getData:(NSInteger)index {
    
    NSArray *temp;
    switch (index) {
        case 0: // scan result
        {
            ProgramTable *pt = [ScanChannel shareInstance].programTable;
            if (pt == nil || !pt.freqPrograms.allValues.count) {
                pt = [NSKeyedUnarchiver unarchiveObjectWithFile:[SandBoxUtil scanProgramTableArchiverPath]];
                [ScanChannel shareInstance].programTable = pt;
            }
        
            if (pt) {
                NSMutableArray *arrM = [NSMutableArray array];
                // 使用 programs
                [arrM addObjectsFromArray:pt.programs];
                temp = arrM;
            }
            else {
                temp = nil;
            }
            break;
        }
        case 1: // favorite
        {
            ProgramTable *pt = [ScanChannel shareInstance].programTable;
            NSArray *arr = pt.favoritePrograms;
            for (Program *p in arr) {
                p.isPlaying = NO;
            }
            temp = arr;
    
            break;
        }
        case 2: // records
        {
#if UseVLCListPlayer
            if (!self.records) {
                self.records = [[DataUtil shareInstance] fetchRecords];
            }
            temp = self.records;
#else
            temp = [[DataUtil shareInstance] fetchRecords];
#endif
            break;
        }
        default:
            break;
    }
    
    // display video state of selection
    for (int i = 0; i < temp.count; i++) {
        Video *video = temp[i];
        if ([video isTheSameAs:self.currentVideo]) video.isPlaying = YES;
        else video.isPlaying = NO;
        
    }
   
    self.videoList.videos = temp;
    [self.videoList setNodataNoticeHidden:(self.videoList.videos.count > 0)];

}

- (void)selectShowAndLoadData:(NSInteger)index {
    for (UIButton *b in self.tabarBtns) {
        b.selected = NO;
    }
    UIButton *btn = self.tabarBtns[index];
    if (self.isFullscreenModel) {
        btn.selected = !btn.selected;
    } else {
        btn.selected = YES;
    }
    
    // get data and refresh
    [self getData:btn.tag];
}

void vlc_epg_dump(vlc_epg_t *p_epg) {
//    NSLog(@"%s--test epg -  : %s", __func__, p_epg->psz_name);
    
//    for (int i = 0; p_epg->i_event; i++) {
//        vlc_epg_event_t *event = p_epg->pp_event[i];
//    }

}


- (void)scanEPG:(Program *)program {
    /////////////// EPG
    __weak typeof(self) weakSelf = self;
    // 清空列表
//    [weakSelf.epgView setProgram:program];
    
    dispatch_async(weakSelf.eit_queue, ^(void) {
        
//        [weakSelf.epgView showData:program];
        
        [[DeviceInterface shareInstance] scan_epg_segmentDumpCallback:^(NSDictionary *items, id param) {
            
            [[EPGDataFilter shareInstance] saveData:[[items allValues] firstObject] frequency:program.frequency program:[[[items allKeys] firstObject] integerValue]];
            
        } totCallback:^(NSDate *date_0x4e, NSDate *date, NSNumber *offset) {
            [[EPGDataFilter shareInstance] setTotDate:date_0x4e frequency:program.frequency];
            if (offset) {
                [[EPGDataFilter shareInstance] setTotOffset:offset];
            }
        }];
        
    });
}

#pragma mark - Button Event
- (void)playCurrentVideo {
    [self playVideo:self.currentVideo];
}

- (void)playButtonClick {
    if (self.player.state == VLCMediaPlayerStateStopped) {
        [self playVideo:self.currentVideo];
        return;
    }
    
    [self play];
}

- (void)pauseButtonClick {
    [self pause];
}

- (void)recordButtonClick:(UIButton *)btn {
    
    __weak typeof(self) weakSelf = self;
    [self.recordingView start:^{
        NSLog(@"%@--%s-- 正在 录制", [weakSelf class], __func__);
        weakSelf.isRecording = YES;
    } stop:^{
        NSLog(@"%@--%s-- 停止 录制", [weakSelf class], __func__);
        weakSelf.isRecording = NO;
    }];
}

- (void)scanButtonClick {
    [self dismissAnimated:NO];
    
    [[DispatchCenter shareInstance] jumpScanViewController];
}

- (void)favoriteButtonClick:(UIButton *)btn {
    
    if (![self.currentVideo isKindOfClass:[Program class]]) return;
    
    Program *currentProgram = (Program *)self.currentVideo;
    ProgramTable *proTable = [ScanChannel shareInstance].programTable;
    if (btn.selected) { // if btn.selected == YES, cancel favorite
        if ([proTable.favoritePrograms containsObject:currentProgram]) {
            [proTable.favoritePrograms removeObject:currentProgram];
        }
        
        btn.selected = NO;
    }
    else {  // favorite
        
        [proTable.favoritePrograms addObject:currentProgram];
        
        btn.selected = YES;
    }
    
    int i = 0;
    BOOL success = NO;
    while (i < 2) {
        success = [NSKeyedArchiver archiveRootObject:proTable toFile:[SandBoxUtil scanProgramTableArchiverPath]];
        if (success) break;
        i++;
    };
}

- (void)closeButtonClick {
    [self dismissAnimated:YES];
}

- (void)fullScreenButtonClick {
    
//    [self forceChangeOrientation:UIInterfaceOrientationLandscapeRight];
    self.isFullscreenModel = YES;
}

- (void)shrinkScreenButtonClick {
    self.isFullscreenModel = NO;
//    [self forceChangeOrientation:UIInterfaceOrientationPortrait];
}

- (void)progressChanged:(UISlider *)slide {
    int targetIntvalue = (int)(slide.value * (float)self.player.media.length.intValue);
    VLCTime *vlcTime = [VLCTime timeWithInt:targetIntvalue];

    [self.controlView.timeLabel setText:vlcTime.stringValue];
    [self.controlView.rTimeLabel setText:self.player.media.length.stringValue];
}

- (void)volumeChanged:(UISlider *)slide {
    self.controlView.systemVolumeSlider.value = slide.value;
}


- (void)progressClick {
    
    int targetIntvalue = (int)(self.controlView.progressSlider.value * (float)self.player.media.length.intValue);
    
    VLCTime *targetTime = [[VLCTime alloc] initWithInt:targetIntvalue];
    
    [self.player setTime:targetTime];
}

- (void)preVideo:(UIButton *)btn {
    // 点击以后 禁用1s, 1s后再激活
    btn.userInteractionEnabled = NO;
    
    [[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateUIViewState:) object:btn];
    [self performSelector:@selector(updateUIViewState:) withObject:btn afterDelay:1.0];
    
    if (self.isRecording) {
        [self.view makeToast:NSLocalizedString(@"recording...", nil) duration:1.0 position:CSToastPositionCenter];
        return;
    }
    
    NSLog(@"%@--%s--%@", [self class], __func__, @"");

    NSInteger index = [self.videos indexOfObject:self.currentVideo];
    index -= 1; // current index
    if (index < 0) {
        index = self.videos.count - 1;
    }
    [self switchVideoIndex:index];
    
}

- (void)nextVideo:(UIButton *)btn {
    // 点击以后 禁用1s, 1s后再激活
    btn.userInteractionEnabled = NO;
    
    [[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateUIViewState:) object:btn];
    [self performSelector:@selector(updateUIViewState:) withObject:btn afterDelay:1.0];
    
    if (self.isRecording) {
        [self.view makeToast:NSLocalizedString(@"recording...", nil) duration:1.0 position:CSToastPositionCenter];
        return;
    }
    
    NSLog(@"%@--%s--%@", [self class], __func__, @"");
    
    NSInteger index = [self.videos indexOfObject:self.currentVideo];
    index += 1; // current index
    if (index > self.videos.count - 1) {
        index = 0;
    }
    [self switchVideoIndex:index];

}

- (void)tapTabarMenuBtn:(UIButton *)btn {
    NSLog(@"%@--%s--%ld", [self class], __func__, btn.tag);
    
//    for (UIButton *b in self.tabarBtns) {
//        b.selected = NO;
//    }
//    if (self.isFullscreenModel) {
//        btn.selected = !btn.selected;
//    } else {
//        btn.selected = YES;
//    }
//
//    // get data and refresh
//    [self getData:btn.tag];
    
    [self selectShowAndLoadData:[self.tabarBtns indexOfObject:btn]];
    
    if (self.isFullscreenModel) {
        // cancel tabarMnu hide
        [self cancelAutoFadeOutTabarMenu];
        
        // videolist hide or not
        self.epgContainerView.hidden = btn.selected;
        [self setFullScreenModeVideoListHidden:!btn.selected];
    }
    
}

- (void)tapLeftMenuBtn:(UIButton *)btn {
    
    if (self.isFullscreenModel) {
        btn.selected = !btn.selected;
    } else {
        btn.selected = YES;
    }
    
    switch (btn.tag) {
        case 0:
        {
            if (self.isFullscreenModel) {
                
                if ([self.currentVideo isKindOfClass:[Program class]]) {
#if PlayProgramOpenScanEPG
                    [self.epgView showData:(Program *)self.currentVideo];
                    
                    // cancel tabarMnu hide
                    [self cancelAutoFadeOutTabarMenu];
                    
                    // EPGView hide or not
                    self.listContainerView.hidden = btn.selected;
                    [self setFullScreenModeEpgViewHidden:!btn.selected];
#endif // PlayProgramOpenScanEPG
                    
                }
            }
        }
            break;
        case 1:
        {
            
            NSString *currentRatio = btn.titleLabel.text?:@"Full";// [NSString stringWithUTF8String:self.player.videoAspectRatio?:"Full"];
            NSInteger index = 0;
            for (NSInteger i = 0; i < self.videoAspectRatios.count; i++) {
                if ([currentRatio isEqualToString:self.videoAspectRatios[i]]) {
                    index = i;
                    break;
                }
            }
            if (index == self.videoAspectRatios.count - 1) index = 0;
            else index++;
            
            self.player.videoCropGeometry = NULL;
            NSString *s_ratio = self.videoAspectRatios[index];

            NSLog(@"%s--screen_ratio: player.videoAspectRatio: %@", __func__, [NSString stringWithUTF8String:self.player.videoAspectRatio?:"Default"]);
            CGFloat screen_ratio = [UIScreen mainScreen].bounds.size.width / [UIScreen mainScreen].bounds.size.height;
            NSString *str_screen_ratio = [NSString stringWithFormat:@"%d:%d", (int)(screen_ratio * 100), 100];
            NSLog(@"%s--screen_ratio: %@", __func__, str_screen_ratio);
            self.player.videoAspectRatio = [s_ratio isEqualToString:@"Full"] ? (char *)[str_screen_ratio UTF8String] : (char *)[s_ratio UTF8String];
            
            //                self.player.videoAspectRatio = [s_ratio isEqualToString:@"Full"] ? NULL : (char *)[s_ratio UTF8String];
        
            self.currentVideoRatio = s_ratio;
            [btn setTitle:s_ratio forState:UIControlStateNormal];

            
            [self cancelAutoFadeOutTabarMenu];
            [self setFullScreenModeEpgViewHidden:YES];
        }
            break;
        case 2:
        {
            self.isLockingScreen = YES;
        }
            break;
        default:
            break;
    }
    
    
    
}

- (void)setFullScreenModeVideoListHidden:(BOOL)isHidden {
    if (!self.isFullscreenModel) return;

    self.videoList.hidden = isHidden;
    
    __weak typeof(self) weakSelf = self;
    if (isHidden) {
        self.controlView.beforeHideBlock = ^{
            [weakSelf animateHideTabarMenu];
        };
        
        // controlView and tabarMnu show
        [self.controlView animateShow];
        
        // recover tabar buton state
        for (UIButton *btn in self.tabarBtns) {
            btn.selected = NO;
        }
        
        // tap extra area to shrink
        [self.listContainerView mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.height.equalTo(self.controlView.mas_height).multipliedBy(0.4);
            make.height.mas_greaterThanOrEqualTo(90);
            make.width.mas_equalTo(50);
            make.right.equalTo(self.controlView);
            make.centerY.equalTo(self.controlView.mas_centerY);
        }];
    }
    else {
        // to make
        self.controlView.beforeHideBlock = nil;
        
        // hide controlView
        [self.controlView animateHide];
        
        [self.controlView bringSubviewToFront:self.listContainerView];
        [self.listContainerView mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.edges.equalTo(self.controlView);
        }];
        
    }
}

- (void)setFullScreenModeEpgViewHidden:(BOOL)isHidden {
    if (!self.isFullscreenModel) return;

    self.epgView.hidden = isHidden;
    
    __weak typeof(self) weakSelf = self;
    if (isHidden) {
        self.controlView.beforeHideBlock = ^{
            [weakSelf animateHideTabarMenu];
        };
        
        // controlView and tabarMnu show
        [self.controlView animateShow];
        
        // recover tabar buton state
        for (UIButton *btn in self.leftBtns) {
            btn.selected = NO;
        }
        
        // tap extra area to shrink
        // epgView 初始化尺寸
        if (self.epgView.superview) {
            [self.epgView mas_remakeConstraints:^(MASConstraintMaker *make) {
                make.width.equalTo(self.epgContainerView).multipliedBy(0.58);
                make.top.bottom.equalTo(self.epgContainerView);
                make.left.equalTo(self.leftMenuView.mas_left);
            }];
            
            [self.epgView removeFromSuperview];
        }
        
        [self.epgContainerView mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.height.equalTo(self.controlView.mas_height).multipliedBy(0.4);
            make.height.mas_greaterThanOrEqualTo(90);
            make.width.mas_equalTo(50);
            make.left.equalTo(self.controlView);
            make.centerY.equalTo(self.controlView.mas_centerY);
        }];
        
    }
    else {
        
        // to make
        self.controlView.beforeHideBlock = nil;
        
        // hide controlView
        [self.controlView animateHide];
        
        [self.controlView bringSubviewToFront:self.epgContainerView];
        [self.epgContainerView mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.edges.equalTo(self.controlView);
        }];
        
        if (nil == self.epgView) {
            self.epgView = [[EPGView alloc] init];
        }
        [self.epgContainerView addSubview:self.epgView];
        
        // epgView 初始化尺寸
        [self.epgView mas_remakeConstraints:^(MASConstraintMaker *make) {
            make.width.equalTo(self.epgContainerView).multipliedBy(0.58);
            make.top.bottom.equalTo(self.epgContainerView);
            make.left.equalTo(self.leftMenuView.mas_left);
        }];
    }
}

- (void)tapListContainerView:(UITapGestureRecognizer *)tapGes {

    // tap extra area to shrink
    [self setFullScreenModeVideoListHidden:YES];
}

- (void)tapEpgContainerView:(UITapGestureRecognizer *)tapGes {
    
    // tap extra area to shrink
    [self setFullScreenModeEpgViewHidden:YES];
}

- (void)updateUIViewState:(UIView *)sender {
    sender.userInteractionEnabled = !sender.userInteractionEnabled;
}

#pragma mark -
- (void)getSignal:(NSTimer *)timer {
    
    if (![self.currentVideo isKindOfClass:[Program class]]) return;
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^(void) {
        
        DTVSignal *signal;
        BOOL success = [[DeviceInterface shareInstance] sft_tvtune_get_signal:&signal];
        
        NSLog(@"%@--%s--%f", [self class], __func__, signal.dPower);
        
        UIImage *image;
#if DebugShow
        NSString *title;
#endif
        
        if (success) {
            //  DVBT
            //  dvbt signal dPower > 0
            if (signal.dPower >= 0) {
                double value = floor(signal.dPower / 20.0);
                value = 5 == value ? 4 : value;
                image = [UIImage imageNamed:[NSString stringWithFormat:@"ic_signal%d", (int)value]];
#if DebugShow
                title = [NSString stringWithFormat:@"%%%d", (int)signal.dPower];
#endif
                
                if (signal.dPower <= 10.0) {
                    // 两分钟显示一次
                    [self showOneNoticePerSecondMinute:NSLocalizedString(@"weak signal", nil)];
                }
            }
            
            //  ISDB-T
            //  ISDB-T tv信号强度表示更改一下：
            //  4格:    > -60 dB
            //  3格:    > -70  && <= -60 dB
            //  2格:    > -80  && <= -70 dB
            //  1格:    > -90  && <= -80 dB
            //  无信号:    <= -90
            //  isdbt signal dPower -> (-20 , -100)
            else {
                
                if (signal.dPower > -60.0) image = [UIImage imageNamed:@"ic_signal4"];
                else {
                    if (signal.dPower > -70.0) image = [UIImage imageNamed:@"ic_signal3"];
                    else {
                        if (signal.dPower > -80.0) image = [UIImage imageNamed:@"ic_signal2"];
                        else {
                            [self showOneNoticePerSecondMinute:NSLocalizedString(@"weak signal", nil)];
                            if (signal.dPower > -90.0) image = [UIImage imageNamed:@"ic_signal1"];
                            else image = [UIImage imageNamed:@"ic_signal0"];
                        }
                    }
                }
#if DebugShow
                title = [NSString stringWithFormat:@"%ddb", (int)signal.dPower];
#endif
            }
        }
        
        // to UI
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            if (success) {
                [self.controlView.singalButton setImage:image forState:UIControlStateNormal];
#if DebugShow
                [self.controlView.singalButton setTitle:title forState:UIControlStateNormal];
#endif
            }
        });
    });
    
}

- (void)showOneNoticePerSecondMinute:(NSString *)info {
    // 两分钟显示一次
    static NSTimeInterval show_ts = 0;
    static NSTimeInterval notice_duration = 60 * 1;
    NSLog(@"%@--%s--TimeInterval: %f", [self class], __func__, show_ts);
    if (!self.player.isPlaying && show_ts + notice_duration < NSDate.timeIntervalSinceReferenceDate) {
        show_ts = NSDate.timeIntervalSinceReferenceDate;
        dispatch_sync_UISafe(^{[self.view makeToast:info duration:2.0 position:CSToastPositionCenter];})
    }
}

- (void)dismissAnimated:(BOOL)animated {
    _is_need_stop = true;
    _is_quit_page = true;
    _is_imem_closed = true;

    _epgView = nil;
    
    //    [self.group_blocks removeAllObjects];
    [self stopVideoAndEixtPage:YES];
    
    clear_variable_queue(&bufQueue);
    
    [self observeDataIsNullOrNot:NO];
    
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
    // 注销通知
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // dismiss or pop
    if (self.navigationController) {
        [self.navigationController popViewControllerAnimated:animated];
    }
    else {
        [self dismissViewControllerAnimated:animated completion:^{
            NSLog(@"%@--%s--%@", [self class], __func__, @"miss 结束");
        }];
    }
    
    _bufferCallback = nil;
}

- (void)observeDataIsNullOrNot:(BOOL)yesOrNo {
    NSLog(@"%@--%s-- : %@", [self class], __func__, yesOrNo ? @"YES" : @"NO");
    
    if (yesOrNo) {
        __weak typeof(self) weakSelf = self;
        [[PlayManager shareInstance] setPerSecondTask:^{
            if (![weakSelf.currentVideo isKindOfClass:[Program class]]) return ;
            
            if (weakSelf.player) { /* FIXME: listplayer.player */
                NSLog(@"%@--%s-- player release issue : PlayerStateBuffering : %@:%d", [weakSelf class], __func__, weakSelf.player.state == VLCMediaPlayerStateBuffering ? @"YES" : @"NO", (int)weakSelf.player.state);
                // 当播放器时间不会走动时, stream not be open (state 不为 VLCMediaPlayerStateBuffering)
                if (weakSelf.player.state != VLCMediaPlayerStateBuffering) {
                    [weakSelf.player changeProgram:(int)((Program *)weakSelf.currentVideo).number];
                    //                    [weakSelf play];
                }
            }
        }];
        
        [[PlayManager shareInstance] startTimeoutTask:^{
            if (![weakSelf.currentVideo isKindOfClass:[Program class]]) return ;
            
            NSLog(@"%@--%s-- player release issue : %@", [weakSelf class], __func__, @"重新播放 _______________");
            [weakSelf switchVideo:weakSelf.currentVideo];
        }];
    }
    else {
        [[PlayManager shareInstance] stopTimeoutTask];
    }
}

#pragma mark - Imem
static ts_queue_t bufQueue;
static bool _is_imem_closed = true;             /// < 默认值为true ,是否已关闭imem
static bool _is_need_stop = false;              /// < 是否已停止节目播放标志
static bool _is_quit_page = false;              /// < 是否退出页面


#define bufferQueueSize streamBufferSize * 25 * 6 // 大概6m以下
#define prefetchReadSize streamBufferSize


#if DebugStreamToFile
static FILE *outputFile;
#endif

NSFileHandle *handle;
uint8_t *getBufWithLen(size_t len, NSFileHandle *handle) {
    
    NSData *data = [handle readDataOfLength:len];
    uint8_t *buf = (uint8_t *)[data bytes];
    
    return buf;
}


int imem_media_open_cb(void *opaque, void **datap, uint64_t *sizep) {
    NSLog(@"%s--len--%llud\n", __FUNCTION__, *sizep);
    NSLog(@"%s-- player release issue : is_need_stop=%d", __func__, _is_need_stop);
    NSLog(@"%s-- player release issue : is_quit_page=%d", __func__, _is_quit_page);
    
#if DebugStreamToFile
    PlayerViewController *self = (__bridge PlayerViewController *)opaque;
    NSLog(@"%@--%s--%p", [self class], __func__, opaque);
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    [fmt setDateFormat:@"MM-dd HH-mm-ss"];
    NSString *name = [NSString stringWithFormat:@"%@_%@_tsbuf.ts", [fmt stringFromDate:[NSDate date]], self.currentVideo.title];
    NSString *filePath = [[SandBoxUtil recordsPath] stringByAppendingPathComponent:name];
    outputFile = fopen([filePath UTF8String], "wb");
#endif
    
    _is_imem_closed = false;
    NSLog(@"%s player release issue : -------open---------------------\n", __FUNCTION__);
    
    if (!bufQueue.abhead) {
        NSLog(@"%s--bufQueue- init \n", __FUNCTION__);
        init_variable_queue(&bufQueue, bufferQueueSize);
    }
    
    NSLog(@"%s--bufQueue.abhead : %p \n", __FUNCTION__, bufQueue.abhead);
    
    return 0;
}

ssize_t imem_media_read_cb(void *opaque, unsigned char *buf, size_t len) {
    NSLog(@"%s--%@", __func__, (__bridge PlayerViewController *)opaque);
    
    ssize_t retSize = 0;
    // 2.
    NSLog(@"--%s-- 开始等待buf  imem need %ld", __func__, len);
    while (!_is_need_stop && is_empty_variable_queue(&bufQueue)) {  /* FIXME: 由于退出播放可能_is_need_stop == true, 若进入播放器不重置为fasle则会退出 */
        if (_is_quit_page) goto end;
        // 太慢会阻碍vlc回调
        usleep(1000);
    }
    
    if (_is_need_stop) {
        //        return 0; // return 0 to close
        goto end;
    }
    
    if (!is_empty_variable_queue(&bufQueue)) {
        int peeksize = peek_variable_queue(&bufQueue, buf, (int)len);
        if (peeksize >= 0) {
            out_variable_queue(&bufQueue, peeksize);
            retSize = peeksize;
            goto end;
        }
        else {
            goto end;
        }
    }
    
end:
    NSLog(@"%s--player release issue : read size: %ld", __func__, retSize);
    return retSize;
}

int imem_media_seek_cb(void *opaque, uint64_t offset) {
    NSLog(@"%s--%@", __func__, (__bridge PlayerViewController *)opaque);
    
    NSLog(@"%s--offset--%llud\n", __FUNCTION__, offset);
    //    if (bufQueue.qsize == bufQueue.qmaxsize) {
    //        return 1024 * 1024 * 5;
    //    }
    
    return 0;
}

void imem_media_close_cb(void *opaque) {
    
    empty_variable_queue(&bufQueue);
    _is_imem_closed = true;
    NSLog(@"%s player release issue : -------close---------------------\n", __FUNCTION__);
    
    
#if DebugStreamToFile
    if (outputFile) fclose(outputFile);
#endif
}

void data_read_callback(void *tsbuf, unsigned int bufsize) {
    // 通过队列缓存
    NSLog(@"--%s-- ts buffer length %uud", __func__, bufsize);
    
    
    // buffering 不等于0时(即在缓存过程中), 要重置超时时间
    if (!_is_need_stop) {
        int entersize = enter_variable_queue(&bufQueue, tsbuf, bufsize, 0);
        NSLog(@"%s---- enter queue length %d", __func__, entersize);
    }
}

#pragma mark - Player Logic
- (void)play {
#if UseVLCListPlayer
    [self.listPlayer play];
#else
    [self.player play];
#endif
    dispatch_async_UISafe(^(void) {
        self.controlView.playButton.hidden = YES;
        self.controlView.pauseButton.hidden = NO;
        NSLog(@"%s--Player Logic : %@", __func__, @"play");
    //    [self.controlView autoFadeOutControlBar];
    });
}

- (void)pause {
#if UseVLCListPlayer
    [self.listPlayer pause];
#else
    [self.player pause];
#endif
    dispatch_async_UISafe(^(void) {
        self.controlView.playButton.hidden = NO;
        self.controlView.pauseButton.hidden = YES;
//    [self.controlView autoFadeOutControlBar];
        NSLog(@"%s--Player Logic : %@", __func__, @"pause");

    });
}

- (void)stop {
#if SwitchVideoNeedStop
#if UseVLCListPlayer
    [self.listPlayer stop];
#else
    [self.player stop];
#endif
#endif

    dispatch_async_UISafe(^(void) {
        self.controlView.progressSlider.value = 1;
        self.controlView.playButton.hidden = NO;
        self.controlView.pauseButton.hidden = YES;
    });
}

- (void)switchVideoIndex:(NSInteger)index {
    [self switchVideo:self.videos[index]];
}

- (void)switchVideo:(Video *)video {
    for (dispatch_block_t block in self.group_blocks) {
        dispatch_block_cancel(block);
    }
    [self.group_blocks removeAllObjects];
    
    [self stopVideoAndEixtPage:NO];
    [self playVideo:video];
}

- (void)playIndex:(NSInteger)index {
    [self playVideo:self.videos[index]];
}

- (void)playVideo:(Video *)video {
    
    // set and save isPlaying
    for (Video *v in self.videos) {
        if([v isEqual:video]) v.isPlaying = YES;
        else v.isPlaying = NO;
    }
    self.currentVideo = video;
    [self.videoList reloadData];
    
    
    // show title and is favorite or not
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.controlView.switchView.titleL.text = video.title;
        self.controlView.titleLabel.text = video.title;
    });
    [self.controlView animateShow];
    
    if ([video isKindOfClass:[Program class]]) {
        
        self.controlView.singalButton.hidden = NO;
        self.controlView.progressSlider.hidden = YES;
        self.controlView.rTimeLabel.hidden = YES;
        self.controlView.separateLine.hidden = YES;
        self.controlView.shouldFunctionBarHidden = NO;
        
        self.audioSourceNoticeView.hidden = !((Program *)video).isAudioSource;
        
        // epg 按钮设置是否可用
        ((UIButton *)[self.leftBtns firstObject]).enabled = YES;
        
        
        // show favorite or not
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            //        ProgramTable *pt = [NSKeyedUnarchiver unarchiveObjectWithFile:[SandBoxUtil favoritePath]];
            ProgramTable *pt = [ScanChannel shareInstance].programTable;
            self.controlView.favoriteButton.selected = (pt && [pt indexForFavoriteProgram:(Program *)video] >= 0);
        });
        
        if (((Program *)video).isScrambling) {
            [[PlayManager shareInstance] setTaskWorkState:NO];
            // epg 按钮设置是否可用
            ((UIButton *)[self.leftBtns firstObject]).enabled = NO;
            [self.view makeToast:NSLocalizedString(@"Encrypted Channel !", nil) duration:2.0 position:CSToastPositionCenter];
            return;
        }
        else {
            [[PlayManager shareInstance] setTaskWorkState:YES];
        }
        
        [self playProgram:(Program *)video];
    }
    else if ([video isKindOfClass:[Record class]]) {
        
        [[PlayManager shareInstance] setTaskWorkState:NO];
        
        self.controlView.singalButton.hidden = YES;
        self.controlView.progressSlider.hidden = NO;
        self.controlView.rTimeLabel.hidden = NO;
        self.controlView.separateLine.hidden = YES;
        self.controlView.shouldFunctionBarHidden = YES;
        
        self.audioSourceNoticeView.hidden = YES;
        
        // epg 按钮设置是否可用
        ((UIButton *)[self.leftBtns firstObject]).enabled = NO;
        
        [self playRecord:(Record *)video];
    }
}

- (void)playRecord:(Record *)record {
    
    NSLog(@"%s--Player Logic : %@", __func__, @"play");
    
#if UseVLCListPlayer
    self.listPlayer.mediaList = self.recordMediaList;
    [self.imemMediaList unlock];
    
    NSInteger index = [self.records indexOfObject:record];
    [self.listPlayer playItemAtNumber:@(index)];
#else
    __weak typeof(self) weakSelf = self;
    dispatch_block_t play_record_block = dispatch_block_create(0, ^{
        weakSelf.player.media = [VLCMedia mediaWithURL:record.url];
        [weakSelf play];
    });
    [self.group_blocks addObject:play_record_block];
    
    dispatch_group_notify(self.play_task_group, self.play_task_queue, play_record_block);
    
#endif
}


- (void)playProgram:(Program *)program {
    NSLog(@"%@--%s--%@", [self class], __func__, @"播放节目-----");
    
#if UseVLCListPlayer
    self.listPlayer.mediaList = self.imemMediaList;
#endif
    
    // schedule to get signal
    //    [self.signalTimer fire];
    
    
    BOOL block = YES;
#if TestFloatBall
    block = ![[self.assistantBall.addtionItems firstObject] hasPrefix:@"!"];
#endif
    
    __weak typeof(self) weakSelf = self;
    
    if (nil == self.bufferCallback) {
        
        self.bufferCallback = ^(void *tsbuf, unsigned int bufsize) {
            // 通过队列缓存
            NSLog(@"%@--%s-- ts buffer length %uud", [weakSelf class], __func__, bufsize);
            NSLog(@"%@--%s--weakSelf.isAppActive : %@", [weakSelf class], __func__, weakSelf.isAppActive ? @"YES" : @"NO");
            
            // epg
#if PlayProgramOpenScanEPG
            dispatch_async(dispatch_get_global_queue(0, 0), ^(void) {
                [[DeviceInterface shareInstance] scan_epg_buffer_entry:tsbuf bufsize:bufsize];
            });
#endif
            
            // buffering 不等于0时(即在缓存过程中), 要重置超时时间
            if (weakSelf.buffering != 0.0) {
#if PlayProgramResetTimeout
                [[PlayManager shareInstance] resetTimeout];
#endif
            }
            if (!_is_need_stop && weakSelf.isAppActive) {
                int entersize = enter_variable_queue(&bufQueue, tsbuf, bufsize, 0);
                NSLog(@"%s--player release issue: enter queue length %d", __func__, entersize);
                
                // 队列满的时候, 做丢弃处理
                if (entersize == -2 || entersize == -1) {
                    NSLog(@"%@--%s--player release issue : %@", [weakSelf class], __func__, @"jump forward");
                    empty_variable_queue(&bufQueue);
                    [weakSelf.player play];
                }
            }
            
#if DebugStreamToFile
            uint8_t *temp = tsbuf;
            int read_paket_count = bufsize / 188;
            int read_fd = 0;
            while (read_fd < read_paket_count) {
                
                temp = tsbuf + read_fd * 188;
                
                // 取得pid
                uint16_t i_pid = ((uint16_t)(temp[1] & 0x1f) << 8) + temp[2];
                if (i_pid == 0x12) {
                    /* Write to file */
                    if ( outputFile != NULL && fwrite (tsbuf, 188, 1, outputFile) != 1 ) {
                        printf ("%s(tips=%s)fwrite failed.\n", __FUNCTION__, "________");
                    }
                }
                
                read_fd++;
            }
            
            
            //            /* Write to file */
            //            if ( outputFile != NULL && fwrite (tsbuf, bufsize, 1, outputFile) != 1 ) {
            //                printf ("%s(tips=%s)fwrite failed.\n", __FUNCTION__, "________");
            //            }
#endif
            
        };
    }
    
    // 网络流过来后创建vlc播放器 , 画面同时性较好
    self.controlView.indicatorView.hidden = NO;
    self.controlView.indicatorView.msgLable.text = @"0%";
    
    
#if UseVLCListPlayer
    dispatch_group_async(self.play_task_group, self.play_task_queue, ^{
        [[ScanChannel shareInstance] filterStream:program block:block bufferCallback:self.bufferCallback complete:^(BOOL success, NSString *errorInfo) {
            NSLog(@"%@--%s--player release issue : 拉流是否成功 : %@", [self class], __func__, success ? @"YES" : @"NO");
            dispatch_semaphore_signal(self.semaphore);
            if (success) {
#if TestFloatBall
                [weakSelf.view makeToast:errorInfo duration:3.0 position:CSToastPositionCenter];
#endif
            }
            else {
                [weakSelf.view makeToast:errorInfo duration:1.0 position:CSToastPositionCenter];
            }
        }];
        
        dispatch_semaphore_wait(self.semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
        NSLog(@"%@--%s-- player release issue : semaphore_wait end", [self class], __func__);
        
    });
    
    dispatch_group_notify(self.play_task_group, self.play_task_queue, ^{
        [weakSelf playProgramWithNumber:(int)program.number];
    });
    
#else
    
    // 正要播放则重置
    [[PlayManager shareInstance] resetTimeout];
    
    dispatch_block_t filter_stream_block = dispatch_block_create(0, ^{
        
        NSLog(@"%@--%s--player release issue : play_task 尝试 %@ 拉流", [weakSelf class], __func__, program.title);
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        [[ScanChannel shareInstance] filterStream:program block:block bufferCallback:weakSelf.bufferCallback complete:^(BOOL success, NSString *errorInfo) {
            NSLog(@"%@--%s--player release issue : play_task %@ 拉流是否成功 : %@", [weakSelf class], __func__, program.title, success ? @"YES" : @"NO");
            NSLog(@"%@--%s--player release issue : semaphore %p", [weakSelf class], __func__, semaphore);
            dispatch_semaphore_signal(semaphore);
            
            dispatch_async_UISafe(^{
                if (success) {
#if TestFloatBall
                    [weakSelf.view makeToast:errorInfo duration:3.0 position:CSToastPositionCenter];
#endif
                }
                else {
                    [weakSelf.view makeToast:errorInfo duration:1.0 position:CSToastPositionCenter];
                }
            });
        }];
        
        dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)); /* FIXME: 快速切换的问题 */
    });
    
    [self.group_blocks addObject:filter_stream_block];
    dispatch_group_async(self.play_task_group, self.play_task_queue, filter_stream_block);
    
    
    dispatch_block_t notify_block = dispatch_block_create(0, ^{
        NSLog(@"%@--%s-- player release issue : play_task play program %d", [weakSelf class], __func__, (int)program.number);
        [weakSelf playProgramWithNumber:(int)program.number];
        
#if PlayProgramOpenScanEPG
        [weakSelf scanEPG:program];
#endif
    });
    [self.group_blocks addObject:notify_block];
    dispatch_group_notify(self.play_task_group, dispatch_get_main_queue(), notify_block);
    
    //    [[ScanChannel shareInstance] filterStream:program block:block bufferCallback:self.bufferCallback complete:^(BOOL success, NSString *errorInfo) {
    //        NSLog(@"%@--%s--player release issue : 拉流是否成功 : %@", [self class], __func__, success ? @"YES" : @"NO");
    //
    //        if (success) {
    //#if TestFloatBall
    //            [weakSelf.view makeToast:errorInfo duration:3.0 position:CSToastPositionCenter];
    //#endif
    //            [weakSelf playProgramWithNumber:(int)program.number];
    //
    //            // EPG
    //            [weakSelf scanEPG:program];
    //        }
    //        else {
    //            [weakSelf.view makeToast:errorInfo duration:1.0 position:CSToastPositionCenter];
    //        }
    //    }];
    
#endif // UseVLCListPlayer
}

- (void)playProgramWithNumber:(int)p_number {
    
#if PlayProgramOpenScanEPG
    //    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    //        [self.player showEpg];
    //    });
#endif
    
#if UseVLCListPlayer
    [[PlayManager shareInstance] resetTimeout];
    NSLog(@"%@--%s-- player release issue : isneed_stop = false", [self class], __func__);
    NSLog(@"%@--%s-- player release issue : player : %@", [self class], __func__, self.listPlayer.mediaPlayer);
    
    [self.listPlayer play];
    [self.listPlayer playItemAtNumber:@(p_number)];
#else
    [[PlayManager shareInstance] resetTimeout];
    
    NSLog(@"%@--%s--player release issue : %@", [self class], __func__, @"set media");
    self.player.media = self.currentMedia;
    self.player.videoAspectRatio = (char *)[self.currentVideoRatio UTF8String];
    [self.player changeProgram:p_number];
    [self play];
#endif
    
    NSLog(@"%@--%s--player release issue : 开始播放节目 %d", [self class], __func__, p_number);
}

- (void)stopVideoAndEixtPage:(BOOL)isExit {
    if ([self.currentVideo isKindOfClass:[Program class]]) {
        [self stopPlayingProgramAndExitPage:isExit];
    }
    else if ([self.currentVideo isKindOfClass:[Record class]]) {
        [self stopPlaying];
    }
}

- (void)stopPlayingRecordAndEixtPage:(BOOL)isExit {
    __weak typeof(self) weakSelf = self;
    dispatch_block_t stop_record_block = dispatch_block_create(0, ^{
        [weakSelf stopPlayingAndExitPage:isExit];
    });
    [self.group_blocks addObject:stop_record_block];
    
    dispatch_group_async(self.play_task_group, self.play_task_queue, stop_record_block);
}

- (void)stopPlayingRecord {
    [self stopPlayingRecordAndEixtPage:NO];
}

- (void)stopPlayingProgramAndExitPage:(BOOL)isExit {
    NSLog(@"%@--%s--%@", [self class], __func__, @"停止播放节目-----");
    
#if UseVLCListPlayer
    [[DeviceInterface shareInstance] stop_scan_epg];
    [[ScanChannel shareInstance] stopFilterStream];
    
    empty_variable_queue(&bufQueue);
    
    __weak typeof(self) weakSelf = self;
    /* FIXME: 需要大量测试不等待停止的情况, 停止播放 */
    dispatch_group_async(self.play_task_group, self.play_task_queue, ^{
        return;
        // 设置结束标识, 退出imem
        NSLog(@"%@--%s-- player release issue : isneed_stop = true", [weakSelf class], __func__);
        _is_need_stop = true;
        
        //        dispatch_async(dispatch_get_global_queue(0, 0), ^(void) {
        // 检测上次播放是否已结束
        int i = 0;
        while (!_is_imem_closed) {
            if (i >= 5000000) return;
            // 防止isimem_closed 未被置为true而去创建player, 导致卡死主界面 runloop为 NSDefaultRunLoopMode可正常触发点击事件, 设为NSRunLoopCommonModes会卡死
            //        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
            //            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            
            // 当前控制器退出时, 队列被释放, 则退出, 防止在此卡住
            if (bufQueue.abhead == NULL) return;
            //        if (_player != nil) return;
            
            
            //        i += 10000;
            //        NSLog(@"%@--%s-- player release issue : %d", [self class], __func__, i);
            usleep(10000);
        }
        _is_need_stop = false;
        //        });
        // 清空播放器
        [weakSelf stopPlayAndRelease];
    });
    
#else
    
    [[DeviceInterface shareInstance] stop_scan_epg];
    
    empty_variable_queue(&bufQueue);
    
    __weak typeof(self) weakSelf = self;
    
    dispatch_block_t stop_program_block = dispatch_block_create(0, ^{
        [[ScanChannel shareInstance] stopFilterStream];
        
        // 设置结束标识, 退出imem
        NSLog(@"%@--%s-- player release issue : play_task isneed_stop = true", [weakSelf class], __func__);
        _is_need_stop = true;
        // 清空播放器
        [weakSelf stopPlayingAndExitPage:isExit];
        
        
        // 检测上次播放是否已结束
        int i = 0;
        while (!_is_imem_closed) {
            if (i >= 5000000) return;
            //            i += 10000;
            //            NSLog(@"%@--%s-- player release issue %d", [self class], __func__, i);
            
            // 当前控制器退出时, 队列被释放, 则退出, 防止在此卡住
            if (_is_quit_page || bufQueue.abhead == NULL) return;
            //        if (_player != nil) return;
            
            usleep(1000);   /* FIXME: 在release版本下不设置睡眠导致线程在此卡住, 10000睡眠表现良好 */
        }
        _is_need_stop = false;
    });
    [self.group_blocks addObject:stop_program_block];
    dispatch_group_async(self.play_task_group, self.play_task_queue, stop_program_block);
    
#endif
}


- (void)stopPlayingProgram {
    [self stopPlayingProgramAndExitPage:NO];
}

- (void)stopPlayingAndExitPage:(BOOL)isExit {
    NSLog(@"%s--Player Logic : stop and eixt : %@", __func__, isExit ? @"YES" : @"NO");
    if (isExit) [self stop];
}

- (void)stopPlaying {
    [self stopPlayingProgramAndExitPage:NO];
}


#pragma mark - TabarMnu/LeftMenuView Hidden or not
- (void)animateHideTabarMenu
{
    [UIView animateWithDuration:SQVideoControlAnimationTimeinterval animations:^{
        self.listContainerView.hidden = YES;
        self.epgContainerView.hidden = YES;
//        self.tabarMenuView.alpha = 0;
//        self.leftMenuView.alpha = 0;
    } completion:^(BOOL finished) {
    }];
}

- (void)animateShowTabarMenu
{
    [UIView animateWithDuration:SQVideoControlAnimationTimeinterval animations:^{
//        self.tabarMenuView.alpha = 1;
//        self.leftMenuView.alpha = 1;
        self.listContainerView.hidden = NO;
        self.epgContainerView.hidden = NO;
    } completion:^(BOOL finished) {
        [self autoFadeOutTabarMenu];
    }];
}

- (void)autoFadeOutTabarMenu
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(animateHideTabarMenu) object:nil];
    [self performSelector:@selector(animateHideTabarMenu) withObject:nil afterDelay:SQVideoControlBarAutoFadeOutTimeinterval];
}

- (void)cancelAutoFadeOutTabarMenu
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(animateHideTabarMenu) object:nil];
}

#pragma mark - VLCMediaPlayerDelegate
- (void)mediaPlayerStateChanged:(NSNotification *)aNotification {
    // Every Time change the state,The VLC will draw video layer on this layer.
    
    self.controlView.centerPlayButton.hidden = YES;
    
    NSLog(@"%@--%s--%ld", [self class], __func__, self.player.media.state);

    switch (self.player.state) {
        case VLCMediaPlayerStateStopped:
            NSLog(@"%@--%s--正在停止播放", [self class], __func__);
            if (![self.currentVideo isKindOfClass:[Program class]]) {
                self.controlView.centerPlayButton.hidden = NO;
            }
//            self.controlView.indicatorView.hidden = YES;
            break;
        case VLCMediaPlayerStateOpening:
            NSLog(@"%@--%s--正在打开", [self class], __func__);
            self.controlView.indicatorView.hidden = NO;
            
            break;
        case VLCMediaPlayerStateBuffering:
        {
            NSLog(@"%@--%s--正在缓存", [self class], __func__);
            self.controlView.indicatorView.hidden = NO;
            float buffering = [aNotification.userInfo[VLCPlayerStateBufferingProgress] floatValue];
            self.buffering = buffering;
            NSLog(@"%@--%s-- player release issue : buffering : %f", [self class], __func__, buffering);

            if (buffering == 1.0) {
                self.controlView.indicatorView.hidden = YES;
            }
            else {
                self.controlView.indicatorView.hidden = NO;
                self.controlView.indicatorView.msgLable.text = [NSString stringWithFormat:@"%.0f%%", buffering * 100];
                NSLog(@"%@--%s--%@", [self class], __func__, [NSString stringWithFormat:@"%.0f%%", buffering * 100]);
            }
        
            if ([self.currentVideo isKindOfClass:[Program class]]) {
                [self.player changeProgram:(int)((Program *)self.currentVideo).number];
                
                if (buffering != 0.0) {
#if PlayProgramResetTimeout
                    [[PlayManager shareInstance] resetTimeout];
#endif
                }
                else [self play];
            }
                
            break;
        }
            
        case VLCMediaPlayerStateEnded:
            NSLog(@"%@--%s--已经结束", [self class], __func__);
            self.controlView.indicatorView.hidden = YES;
            
            [self pause];
            break;
        case VLCMediaPlayerStateError:
            NSLog(@"%@--%s--播放错误", [self class], __func__);
            
            break;
        case VLCMediaPlayerStatePlaying:
            NSLog(@"%@--%s--是否正在播放 : %@", [self class], __func__, self.player.isPlaying ? @"YES" : @"NO");
            self.controlView.indicatorView.hidden = YES;
            
            break;
        case VLCMediaPlayerStatePaused:
            self.controlView.indicatorView.hidden = YES;
            NSLog(@"%@--%s--%@", [self class], __func__, @"VLCMediaPlayerStatePaused");
            break;
        case VLCMediaPlayerStateESAdded:
            NSLog(@"%@--%s--%@", [self class], __func__, @"VLCMediaPlayerStateESAdded");
            break;
            
        default:
            self.controlView.indicatorView.hidden = NO;
            break;
    }
}

- (void)mediaPlayerTimeChanged:(NSNotification *)aNotification {
    
    if (self.controlView.progressSlider.state != UIControlStateNormal) {
        return;
    }
    
    // hidden状态不同的时候, 进行修改
    static int pre_timestamp = 0;
    // 信号量不好的时候, mediaPlayerTimeChanged: 回调会invoke, 但是有时时间都是00:00
    NSLog(@"%@--%s--controlView indicatorView: %d", [self class], __func__, pre_timestamp);
//    (self.controlView.indicatorView.hidden == (self.player.time.intValue > pre_timestamp)) ?1: (self.controlView.indicatorView.hidden = self.player.time.intValue > pre_timestamp);
    self.controlView.indicatorView.hidden = YES;
    pre_timestamp = self.player.time.intValue;
    
    // 处理异常, 超过24小时的视频(因为一般没有超过24小时的视频)
    int sumlength = self.player.media.length.intValue;
    if (self.player.media.length.intValue > 3600 * 24 * 1000) { // 时间单位 mm
        sumlength = self.player.time.intValue;
    }
    
    float precentValue = ([self.player.time.value floatValue]) / (sumlength == 0 ? 1.0 : sumlength);
    [self.controlView.progressSlider setValue:precentValue animated:YES];


#if UseVLCListPlayer
    [self.controlView.timeLabel setText:_listPlayer.mediaPlayer.time.stringValue];
    [self.controlView.rTimeLabel setText:(sumlength == 0 ? @"--:--" : [VLCTime timeWithInt:sumlength].stringValue)];
    
    NSLog(@"%@--%s--%@", [self class], __func__, _listPlayer.mediaPlayer.time.stringValue);
#else
    [self.controlView.timeLabel setText:_player.time.stringValue];
    [self.controlView.rTimeLabel setText:(sumlength == 0 ? @"--:--" : [VLCTime timeWithInt:sumlength].stringValue)];
    
    NSLog(@"%@--%s--%@", [self class], __func__, self.player.time.stringValue);
#endif

}

#pragma mark - SQVideoControlViewDelegate
- (void)controlViewFingerMoveLeft:(SQVideoControlView *)controlView {
    
    // 点击以后 禁用1s, 1s后再激活
    controlView.userInteractionEnabled = NO;
    
    [[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateUIViewState:) object:controlView];
    [self performSelector:@selector(updateUIViewState:) withObject:controlView afterDelay:1.0];
    
//    [self.player shortJumpBackward];
    NSLog(@"%@--%s--%@", [self class], __func__, @"快退");
    
    if ([self.currentVideo isKindOfClass:[Program class]]) {
        [self preVideo:nil];
        [self.controlView.alertlable configureWithTitle:self.currentVideo.title isLeft:YES];
    }

}

- (void)controlViewFingerMoveRight:(SQVideoControlView *)controlView {
    
    // 点击以后 禁用1s, 1s后再激活
    controlView.userInteractionEnabled = NO;
    
    [[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateUIViewState:) object:controlView];
    [self performSelector:@selector(updateUIViewState:) withObject:controlView afterDelay:1.0];
    
//    [self.player shortJumpForward];
    NSLog(@"%@--%s--%@", [self class], __func__, @"快进");
    
    
    if ([self.currentVideo isKindOfClass:[Program class]]) {
        [self nextVideo:nil];
        [self.controlView.alertlable configureWithTitle:self.currentVideo.title isLeft:NO];
    }
}

- (void)controlViewFingerMoveUp {
    
    self.controlView.systemVolumeSlider.value += 0.05;
}

- (void)controlViewFingerMoveDown {
    
    self.controlView.systemVolumeSlider.value -= 0.05;
}

#pragma mark -
// touchesBegan 会跟 tap等手势冲突
//- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
//    UITouch *touch = [touches anyObject];
//    if ([touch.view isEqual:self.listContainerView]) {
//        // tap extra area to shrink
//    }
//}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (!self.listContainerView.hidden) {
        CGPoint point = [touch locationInView:self.listContainerView];
        if (CGRectContainsPoint(self.videoList.frame, point) ||
            CGRectContainsPoint(self.tabarMenuView.frame, point)) {
            return NO;
        }
    }
    else if (!self.epgContainerView.hidden) {
        CGPoint point = [touch locationInView:self.epgContainerView];
        if (CGRectContainsPoint(self.epgView.frame, point) ||
            CGRectContainsPoint(self.leftMenuView.frame, point)) {
            return NO;
        }
    }
    return YES;
}

#pragma mark - UICollectionViewDelegateFlowLayout | UICollectionViewDelegate
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
#if ViewShouldPerSecondForOneTap
    // 点击以后 禁用1s, 1s后再激活
    collectionView.userInteractionEnabled = NO;
    
    [[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateUIViewState:) object:collectionView];
    [self performSelector:@selector(updateUIViewState:) withObject:collectionView afterDelay:1.0];
#endif
    
    if (self.isRecording) {
        [self.view makeToast:NSLocalizedString(@"recording...", nil) duration:1.0 position:CSToastPositionCenter];
        return;
    }
    
    if (self.isFullscreenModel) {
        [self setFullScreenModeVideoListHidden:YES];
    }
    
    
    // 获取点击列表数据源, 在不同列表切换时使用
    self.videos = self.videoList.videos;
    [self switchVideoIndex:indexPath.row];
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    
    if (self.isFullscreenModel) {
        return CGSizeMake(self.view.frame.size.width * 0.38, 50.0);
    }
    else {
        return CGSizeMake((self.view.frame.size.width - 2) / 2, 50.0);//(self.view.frame.size.width - 2) / 3
    }
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    return 1.0;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout minimumInteritemSpacingForSectionAtIndex:(NSInteger)section {
    return 1.0;
}

#pragma mark - Property
- (NSCondition *)conlock {
    if (!_conlock) {
        _conlock = [[NSCondition alloc] init];
    }
    return _conlock;
}

- (NSTimer *)signalTimer {
    if (!_signalTimer) {
        _signalTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(getSignal:) userInfo:nil repeats:YES];
    }
    return _signalTimer;
}

#if UseVLCListPlayer
- (VLCMediaListPlayer *)listPlayer {
    if (!_listPlayer) {
        _listPlayer = [[VLCMediaListPlayer alloc] initWithDrawable:self.drawableView];
        _listPlayer.mediaList = [[VLCMediaList alloc] initWithArray:self.imemMedias];
        //        _listPlayer.mediaList = [[VLCMediaList alloc] initWithArray:self.recordMedias];
        //        _listPlayer.rootMedia = [self.mediaArrM firstObject];
        _listPlayer.repeatMode = VLCDoNotRepeat;
        
        _player = _listPlayer.mediaPlayer;
        _player.delegate = self;
    }
    return _listPlayer;
}

- (VLCMediaList *)imemMediaList {
    if (!_imemMediaList) {
        _imemMediaList = [[VLCMediaList alloc] initWithArray:self.imemMedias];
    }
    return _imemMediaList;
}

- (VLCMediaList *)recordMediaList {
    if (!_recordMediaList) {
        _recordMediaList = [[VLCMediaList alloc] initWithArray:self.recordMedias];
    }
    return _recordMediaList;
}

- (NSArray *)recordMedias {
    if (!_recordMedias) {
        NSMutableArray *arrM = [NSMutableArray array];
        for (Record *record in [[DataUtil shareInstance] fetchRecords]) {
            [arrM addObject:[VLCMedia mediaWithURL:record.url]];
        }
        self.recordMedias = arrM;
    }
    return _recordMedias;
}

- (NSMutableArray *)imemMedias {
    if (!_imemMedias) {
        _imemMedias = [NSMutableArray array];
        
        for (Video *video in self.videos) {
            
            VLCMedia *media = [[VLCMedia alloc] initWithOpenCb:imem_media_open_cb
                                                        readCb:imem_media_read_cb
                                                        seekCb:imem_media_seek_cb
                                                       closeCb:imem_media_close_cb
                                                        opaque:(__bridge void *)(self)];
            [_imemMedias addObject:media];
        }
        
    }
    return _imemMedias;
}

#else

- (VLCMediaPlayer *)player {
    if (!_player) {
        NSArray *options = @[
//                             @"--clock-synchro=1",
//                             @"--video-title-show",
                             @"--sub-track=0",
                             @"--no-ts-trust-pcr",
                             
                             //--sout-transcode-osd, --no-sout-transcode-osd OSD 菜单 (默认关闭) 流式化屏幕显示菜单 (使用 osd 菜单子画面模块)。
                             //--osd, --no-osd 屏幕显示 (默认开启) VLC 可以在视频上显示消息。这被称为 OSD
                             @"--osd",
                             @"--sout-transcode-osd",
                             
                             // 字幕颜色 --> 可能在参数部分 1. Marquee display  2. Freetype2 font renderer
                             @"--freetype-background-opacity=255",
//                             @"--subsdelay-min-alpha=0",
//                             @"--dvbsub-position=10",
//                             @"--dvdsub-transparency",
                             
                             
//                             @"--network-caching=2000",  // 可能导致release_media错误, EXC_BAD_ACCESS
//                             @"--sout-avcodec-rc-buffer-size=100"
//                             @"--vbi-text",
//                             @"--key-subtitle-toggle=1"
                             
//                             @"--longhelp",
//                             @"--advanced",
                             ];
        
//        _player = [[VLCMediaPlayer alloc] initWithOptions:options];
//        _player = [[VLCMediaPlayer alloc] initWithLibVLCInstance:[VLCLibrary sharedLibrary].instance andLibrary:[VLCLibrary sharedLibrary]];
        _player = [[VLCMediaPlayer alloc] init];
        _player.drawable = self.drawableView;
        _player.delegate = self;
        NSLog(@"%@--%s--player release issue : 播放器创建 %@", [self class], __func__, @"");
        
#ifdef DEBUG
        _player.libraryInstance.debugLogging = YES;
        _player.libraryInstance.debugLoggingLevel = 0;
#endif
        NSLog(@"%@--%s--%@", [self class], __func__, _player.libraryInstance.version);
        
    }
    return _player;
}

- (VLCMedia *)currentMedia {
//    if (!_currentMedia) {
        VLCMedia *media = [[VLCMedia alloc] initWithOpenCb:imem_media_open_cb
                                                    readCb:imem_media_read_cb
                                                    seekCb:imem_media_seek_cb
                                                   closeCb:imem_media_close_cb
                                                    opaque:(__bridge void * _Nonnull)(self)];
        
        [media addOptions:@{
//                            @"input-timeshift-granularity":@(1 * 1024 * 1024),
//                            @"prefetch-buffer-size":@(1 * 1024 * 1024), // 默认是 16 * 1024 * 1024
                            @"prefetch-read-size":@(prefetchReadSize), // 默认是 16 * 1024
                            
                            // 字幕颜色 --> 可能在参数部分 1. Marquee display  2. Freetype2 font renderer
                            @"freetype-background-opacity":@255,
                            //                             @"--subsdelay-min-alpha=0",
                            //                             @"--dvbsub-position=10",
                            //                             @"--dvdsub-transparency",
                            }];
        _currentMedia = media;
//    }
    return _currentMedia;
}

#endif // UseVLCListPlayer

- (UIView *)drawableView {
    if (!_drawableView) {
        _drawableView = [[UIView alloc] init];
    }
    return _drawableView;
}

- (NSArray *)videoAspectRatios {
    if (!_videoAspectRatios) {
        _videoAspectRatios = @[@"Full", @"4:3", @"1:1"];
    }
    return _videoAspectRatios;
}

- (RecordingView *)recordingView {
    if (!_recordingView) {
        _recordingView = [[RecordingView alloc] init];
    }
    return _recordingView;
}

- (NSArray<UIButton *> *)tabarBtns {
    if (!_tabarBtns) {
        NSArray *images = @[@"ic_isdbt", @"ic_favorite_video", @"ic_record_video"];
        NSArray *sel_images = @[@"ic_isdbt_sle", @"ic_favorited_video", @"ic_recorded_video"];

        NSMutableArray<UIButton *> *arrM = [NSMutableArray array];
        for (int i = 0; i < images.count; i++) {
            UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
            btn.tag = i;
            [btn setImage:[UIImage imageNamed:images[i]] forState:UIControlStateNormal];
            [btn setImage:[UIImage imageNamed:sel_images[i]] forState:UIControlStateSelected];
//            [btn setBackgroundImage:[UIImage imageNamed:@"channel_default"] forState:UIControlStateNormal];
//            [btn setBackgroundImage:[UIImage imageNamed:@"channel_select"] forState:UIControlStateSelected];
            [btn setBackgroundColor:SQRGB(27, 27, 27)];
            [btn setContentHorizontalAlignment:UIControlContentHorizontalAlignmentCenter];
            [btn addTarget:self action:@selector(tapTabarMenuBtn:) forControlEvents:UIControlEventTouchUpInside];
            [arrM addObject:btn];
        }
        _tabarBtns = arrM;
    }
    return _tabarBtns;
}

- (NSArray<UIButton *> *)leftBtns {
    if (!_leftBtns) {
        
        NSMutableArray<UIButton *> *arrM = [NSMutableArray array];
        for (int i = 0; i < 3; i++) {
            UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
            btn.tag = i;
            if (i== 0) {
                btn.titleLabel.font = [UIFont systemFontOfSize:13.0];
                [btn setTitle:@"EPG" forState:UIControlStateNormal];
            }
            if (i == 1) {
                btn.titleLabel.font = [UIFont systemFontOfSize:13.0];
                [btn setTitle:@"Full" forState:UIControlStateNormal];
            }
            else if (i == 2) {
                [btn setImage:[UIImage imageNamed:@"lock"] forState:UIControlStateNormal];
            }
#if defined(RelNATDTV) || defined(LYTV)
            [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
#else
            [btn setTitleColor:kTintColor forState:UIControlStateNormal];
//            [btn setTitleColor:kButtonSelTextColor forState:UIControlStateSelected];
#endif
            [btn setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];

            [btn setBackgroundColor:SQRGB(27, 27, 27)];
            [btn setContentHorizontalAlignment:UIControlContentHorizontalAlignmentCenter];
            [btn addTarget:self action:@selector(tapLeftMenuBtn:) forControlEvents:UIControlEventTouchUpInside];
            [arrM addObject:btn];
        }
        _leftBtns = arrM;
    }
    return _leftBtns;
}

- (VideoList *)videoList {
    if (!_videoList) {
        //创建表格视图
//        CGFloat width = 0;//self.view.frame.size.width * 0.3;
//        CGFloat space = 10.0f;
        UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
//        layout.itemSize = CGSizeMake(width * 0.3 - 2, 50.0);
//        layout.minimumLineSpacing = 1.0;
//        layout.minimumInteritemSpacing = 1.0;
        
//        CGRect rect = CGRectMake(0, 0, width, width);
        _videoList = [[VideoList alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
        _videoList.backgroundColor = SQRGB(27, 27, 27);
        _videoList.delegate = self;
        
    }
    return _videoList;
}

- (PlayerLockView *)lockView {
    if (!_lockView) {
        __weak typeof(self) weakSelf = self;
        _lockView = [PlayerLockView playerLockViewWithUnlockBlcok:^{
            weakSelf.isLockingScreen = NO;
        }];
    }
    return _lockView;
}

- (SQVideoControlView *)controlView {
    if (!_controlView) {
        _controlView = [[SQVideoControlView alloc] init];
        _controlView.delegate = self;
    }
    return _controlView;
}

- (UIView *)videoContainerView {
    if (!_videoContainerView) {
        _videoContainerView = [UIView new];
    }
    return _videoContainerView;
}

- (UIImageView *)audioSourceNoticeView {
    if (!_audioSourceNoticeView) {
        _audioSourceNoticeView = [[UIImageView alloc] init];
        _audioSourceNoticeView.image = [UIImage imageNamed:@"radio_notice.png"];
    }
    return _audioSourceNoticeView;
}

- (UIView *)listContainerView {
    if (!_listContainerView) {
        _listContainerView = [UIView new];
        _listContainerView.clipsToBounds = YES;
        UITapGestureRecognizer *tapGes = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapListContainerView:)];
        tapGes.delegate = self;
        [_listContainerView addGestureRecognizer:tapGes];
    }
    return _listContainerView;
}

- (UIView *)epgContainerView {
    if (!_epgContainerView) {
        _epgContainerView = [UIView new];
        _epgContainerView.clipsToBounds = YES;
        UITapGestureRecognizer *tapGes = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapEpgContainerView:)];
        tapGes.delegate = self;
        [_epgContainerView addGestureRecognizer:tapGes];
    }
    return _epgContainerView;
}

- (UIView *)tabarMenuView {
    if (!_tabarMenuView) {
        _tabarMenuView = [UIView new];
        _tabarMenuView.backgroundColor = [UIColor blackColor];
    }
    return _tabarMenuView;
}

- (UIView *)leftMenuView {
    if (!_leftMenuView) {
        _leftMenuView = [UIView new];
        _leftMenuView.backgroundColor = [UIColor blackColor];
    }
    return _leftMenuView;
}

- (void)setIsRecording:(BOOL)isRecording {
    _isRecording = isRecording;
    
    if (self.player) {
        [self.player toggleRecord:[SandBoxUtil recordsPath]];
    }
    
    if (_isRecording) {
        self.controlView.hidden = YES;
        
        [self.videoContainerView addSubview:self.recordingView];
        [self.recordingView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.edges.equalTo(self.videoContainerView);
        }];
    }
    else {
        self.controlView.hidden = NO;
        if (self.isFullscreenModel) [self autoFadeOutTabarMenu];
        [self.controlView autoFadeOutControlBar];
        
        if ([self.recordingView isDescendantOfView:self.view]) {
            [self.recordingView removeFromSuperview];
        }
    }
}

- (void)setIsLockingScreen:(BOOL)isLockingScreen {
    _isLockingScreen = isLockingScreen;
    
    if (_isLockingScreen) {
        self.controlView.hidden = YES;
        
        [self.videoContainerView addSubview:self.lockView];
        [self.lockView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.edges.equalTo(self.videoContainerView);
        }];
    }
    else {
        self.controlView.hidden = NO;
        [self autoFadeOutTabarMenu];
        [self.controlView autoFadeOutControlBar];
        
        [self.lockView removeFromSuperview];
    }
    
    
}

- (void)setIsFullscreenModel:(BOOL)isFullscreenModel {
    if (isFullscreenModel == _isFullscreenModel) return;
    
    _isFullscreenModel = isFullscreenModel;
  
    [self initLandscapeOrPortrait:!_isFullscreenModel];
}



@end
