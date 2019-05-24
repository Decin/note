//
//  GLView.h
//  testOpenGLES3
//
//  Created by SQ on 2017/2/9.
//  Copyright © 2017年 HT. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <GLKit/GLKit.h>

@interface HTTriDPicView : GLKView
{
    CAEAGLLayer *_eaglLayer;
    EAGLContext *glContext;
    
    GLuint program;
    GLuint tempProgram;
    
    //GLuint mytexture[2];
    
    //GLuint mExtraFBO;
    
    GLuint _renderbuffer;
    GLuint _framebuffer;
    GLuint _fbo;
    
    GLuint colorTexId[2];
    GLuint _imageTexture;
    
    GLint  _imageWidth;
    GLint  _imageHeight;
    
    GLint  _backingWidth;
    GLint  _backingHeight;
    
    GLuint vertexBuffer;
    GLuint vertexToScreenBuffer;
    //GLuint vertexBufferR;
    
    GLint defaultFramebuffer ;
    
}

@property (strong, nonatomic) UIImage *image;


@end
