//
//  PlayerViewController.h
//  WiFiDisk
//
//  Created by NS on 2017/8/21.
//  Copyright © 2017年 Decin. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface PlayerViewController : UIViewController
/**
 program or record
 */
@property (strong, nonatomic) NSArray *videos;

//@property (strong, nonatomic) ProgramTable *currentFavoritePT;          /// < temporarily save program table of current favorite video that is going to play


/**
 play program or record

 @param index of program or record; program or record
 */
- (void)playIndex:(NSInteger)index;
- (void)playVideo:(id)video;

@end
