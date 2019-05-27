//
//  AudioVideoEditor.h
//  AudioVideoEdit
//
//  Created by SQ on 2019/5/27.
//  Copyright © 2019 ShiftTime. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface AudioVideoEditor : NSObject
/**
 音视频剪辑
 
 @param assetURL  音视频资源路径
 @param startTime 开始剪辑的时间
 @param endTime 结束剪辑的时间
 @param completionHandle 剪辑完成后的回调
 */
+ (void)cutAudioVideoResourcePath:(NSURL *)assetURL startTime:(CGFloat)startTime endTime:(CGFloat)endTime complition:(void (^)(NSURL *outputPath,BOOL isSucceed)) completionHandle;


/**
 音视频合成
 
 @param assetURL 原始视频路径
 @param BGMPath 背景音乐路径
 @param needOriginalVoice 是否添加原视频的声音
 @param videoVolume 视频音量
 @param BGMVolume 背景音乐音量
 @param completionHandle 合成后的回调
 */
+ (void)editVideoSynthesizeVieoPath:(NSURL *)assetURL BGMPath:(NSURL *)BGMPath  needOriginalVoice:(BOOL)needOriginalVoice videoVolume:(CGFloat)videoVolume BGMVolume:(CGFloat)BGMVolume complition:(void (^)(NSURL *outputPath,BOOL isSucceed)) completionHandle;

@end
