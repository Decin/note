//
//  GLView.m
//  testOpenGLES3
//
//  Created by SQ on 2017/2/9.
//  Copyright © 2017年 HT. All rights reserved.
//

#import "HTTriDPicView.h"
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/ES3/glext.h>


@interface HTTriDPicView (){
    CGFloat x_ratio;
    CGFloat y_ratio;
}


@end

@implementation HTTriDPicView


typedef struct
{
    float position[4];
    float textureCoordinateL[2];
    float textureCoordinateR[2];
} CustomVertex;

typedef struct
{
    float position[4];
    float textureCoordinate[2];
} CustomVertexToScreen;

enum
{
    ATTRIBUTE_POSITION = 0,
    ATTRIBUTE_INPUT_TEXTURE_COORDINATE,
    TEMP_ATTRIBUTE_POSITION,
    TEMP_ATTRIBUTE_INPUT_TEXTURE_COORDINATE_L,
    TEMP_ATTRIBUTE_INPUT_TEXTURE_COORDINATE_R,
    NUM_ATTRIBUTES
};
GLint ViewAttributes[NUM_ATTRIBUTES];

enum
{
    UNIFORM_INPUT_IMAGE_TEXTURE_L = 0,
    UNIFORM_INPUT_IMAGE_TEXTURE_R ,
    TEMP_UNIFORM_INPUT_IMAGE_TEXTURE,
    UNIFORM_TEMPERATURE,
    UNIFORM_SATURATION,
    NUM_UNIFORMS
};
GLint ViewUniforms[NUM_UNIFORMS];


+ (Class)layerClass {
    return [CAEAGLLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
    
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    NSLog(@"----layoutSubviews----视图改变----");
    /*[self setBuffer];
     
     glBindRenderbuffer(GL_RENDERBUFFER, _renderbuffer);
     [glContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:_eaglLayer];
     
     glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_backingWidth);//750
     glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_backingHeight);//1334
     [self initFBO];
     GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
     if (status != GL_FRAMEBUFFER_COMPLETE) {
     
     NSLog(@"failed to make complete framebuffer object %x", status);
     
     } else {
     
     NSLog(@"OK setup GL framebuffer %d:%d", _backingWidth, _backingHeight);
     }
     
     //[self setContext];
     
     */
    
    
    //[self update];
}

- (void)update{
    [self setContext];
    
    [self setBuffer];
    
    [self setImageToTextrue];
    
    [self initFBO];
    
    [self loadShaders];
    
    [self loadTempShader];
    
    [self setupVBOs];
    
    [self render];
}



- (void)setContext{
    _eaglLayer = (CAEAGLLayer *)self.layer;
    //  CALayer默认是透明的，而透明的层对性能负荷很大。所以将其关闭。
    _eaglLayer.opaque = YES;
    
    glContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    
    if (!glContext) {
        NSLog(@"Failed to create ES context");
    }
    
    
    //GLKView *view = (GLKView *)self;
    //view.context = glContext;
    //        view.drawableColorFormat = GLKViewDrawableColorFormatSRGBA8888;
    //        view.drawableDepthFormat = GLKViewDrawableDepthFormat24;
    
    [EAGLContext setCurrentContext:glContext];
    
    GLint params;
    glGetIntegerv(GL_MAX_VERTEX_TEXTURE_IMAGE_UNITS, &params);
    NSLog(@"GL_MAX_VERTEX_TEXTURE_IMAGE_UNITS = %zi", params);
    glGetIntegerv(GL_MAX_TEXTURE_IMAGE_UNITS, &params);
    NSLog(@"GL_MAX_TEXTURE_IMAGE_UNITS = %zi", params);
    
    //glBindFramebuffer(GL_FRAMEBUFFER, 0);
    //glBindTexture(GL_TEXTURE_2D, 0);
    
}


- (void)setupTextureWithImage:(UIImage *)image {
    _imageWidth = (GLint)CGImageGetWidth(image.CGImage);
    _imageHeight = (GLint)CGImageGetHeight(image.CGImage);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    void *imageData = malloc( _imageWidth * _imageHeight * 4 );
    
    CGContextRef context = CGBitmapContextCreate(imageData,
                                                 _imageWidth,
                                                 _imageHeight,
                                                 8,
                                                 4 * _imageWidth,
                                                 colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    
    CGColorSpaceRelease( colorSpace );
    CGContextClearRect( context, CGRectMake( 0, 0, _imageWidth, _imageHeight ) );
    CGContextTranslateCTM(context, 0, _imageHeight);
    CGContextScaleCTM (context, 1.0, -1.0);
    CGContextDrawImage( context, CGRectMake( 0, 0, _imageWidth, _imageHeight ), image.CGImage );
    CGContextRelease(context);
    
    glActiveTexture(GL_TEXTURE0);
    glGenTextures(1, &_imageTexture);
    glBindTexture(GL_TEXTURE_2D, _imageTexture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER,GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER,GL_LINEAR);
    glTexImage2D(GL_TEXTURE_2D,
                 0,
                 GL_RGBA,
                 _imageWidth,
                 _imageHeight,
                 0,
                 GL_RGBA,
                 GL_UNSIGNED_BYTE,
                 imageData);
    

    
    //glBindFramebuffer(GL_FRAMEBUFFER, _tempFrameBuffer);
    //glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, _imageTexture, 0);
    free(imageData);
    
    NSLog(@"_imageTexture = %d", _imageTexture);
    
}

-(void)initFBO
{
    if(_fbo)
    {
        glDeleteFramebuffers(1, &_fbo);
        _fbo = 0;
    }
    
    glGenFramebuffers(1, &_fbo);  //fbo
    glBindFramebuffer(GL_FRAMEBUFFER, _fbo);
    
    glGenTextures (2, &colorTexId[0]);
    //NSLog(@"%p, %p, %d, %d",colorTexId, &colorTexId, colorTexId[0], colorTexId[1]);
    
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, colorTexId[0]);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, _imageWidth, (GLint)_imageHeight, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glFramebufferTexture2D(GL_FRAMEBUFFER, mrt[0], GL_TEXTURE_2D, colorTexId[0], 0);
    
    glActiveTexture(GL_TEXTURE2);
    glBindTexture(GL_TEXTURE_2D, colorTexId[1]);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (GLint)_imageWidth, (GLint)_imageHeight, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glFramebufferTexture2D(GL_FRAMEBUFFER, mrt[1], GL_TEXTURE_2D, colorTexId[1], 0);
    
    //    glDrawBuffers(2, mrt);
    
    /*
    CGFloat w = _imageWidth;
    CGFloat h = _imageHeight;
    
    //横屏状态下
    CGFloat img_ratio = w / h;
    CGFloat screen_ratio = KScreenW / KScreenH;
    
    
    if (img_ratio >= screen_ratio) {
        //x横向宽度占屏幕宽的比例
        y_ratio = 2 - img_ratio * screen_ratio;
        x_ratio = 1.0;
    }else{
        x_ratio = 2 - img_ratio / screen_ratio;
        y_ratio = 1.0;
    }*/
    
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    
    NSString *errorMessage = nil;
    switch (status)
    {
        case GL_FRAMEBUFFER_UNSUPPORTED:
            errorMessage = @"framebuffer不支持该格式";
            break;
        case GL_FRAMEBUFFER_COMPLETE:
            NSLog(@"framebuffer 创建成功");
            break;
        case GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT:
            errorMessage = @"Framebuffer不完整 缺失组件";
            break;
        case GL_FRAMEBUFFER_INCOMPLETE_DIMENSIONS:
            errorMessage = @"Framebuffer 不完整, 附加图片必须要指定大小";
            break;
        default:
            // 一般是超出GL纹理的最大限制
            errorMessage = @"未知错误 error !!!!";
            break;
    }
    
    glBindFramebuffer ( GL_FRAMEBUFFER, _framebuffer );
    
    NSLog(@"%@",errorMessage);
    
}

- (void)setImageToTextrue{

    [self setupTextureWithImage:_image];
}

- (void)setBuffer{//2
    
    if(_framebuffer)
    {
        glDeleteFramebuffers(1, &_framebuffer);
        _framebuffer = 0;
    }
    
    if(_renderbuffer)
    {
        glDeleteRenderbuffers(1, &_renderbuffer);
        _renderbuffer = 0;
    }
    
    
    glGenRenderbuffers(1, &_renderbuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, _renderbuffer);
    [glContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:_eaglLayer];
    
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_backingWidth);//750
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_backingHeight);//1334

    
    
    glGenFramebuffers(1, &_framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER,_renderbuffer);
    
    NSLog(@"_renderbuffer = %d", _renderbuffer);
    NSLog(@"_framebuffer = %d", _framebuffer);
    NSLog(@"_backingWidth = %d", _backingWidth);
    NSLog(@"_backingHeight = %d", _backingHeight);
    
}

- (void)setupVBOs {
    
    static const CustomVertex vertices[] =
    {
        { .position = { -1.0,  1.0, 0, 1 }, .textureCoordinateL = { 0.0, 1.0 }, .textureCoordinateR = { 0.5, 1.0 } },
        { .position = {  1.0,  1.0, 0, 1 }, .textureCoordinateL = { 0.5, 1.0 }, .textureCoordinateR = { 1.0, 1.0 } },
        { .position = { -1.0, -1.0, 0, 1 }, .textureCoordinateL = { 0.0, 0.0 }, .textureCoordinateR = { 0.5, 0.0 } },
        { .position = {  1.0, -1.0, 0, 1 }, .textureCoordinateL = { 0.5, 0.0 }, .textureCoordinateR = { 1.0, 0.0 } }
    };
    const CustomVertexToScreen verticesToScreen[] =
    {
        
        { .position = {  1.0,  1.0, 0, 1 }, .textureCoordinate = { 1.0 , 1.0 } },
        { .position = {  1.0, -1.0, 0, 1 }, .textureCoordinate = { 1.0 , 0.0 } },
        { .position = { -1.0,  1.0, 0, 1 }, .textureCoordinate = { 0.0, 1.0 } },
        { .position = { -1.0, -1.0, 0, 1 }, .textureCoordinate = { 0.0, 0.0 } }
    };
    
    glGenBuffers(1, &vertexBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
    
    glGenBuffers(1, &vertexToScreenBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, vertexToScreenBuffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(verticesToScreen), verticesToScreen, GL_STATIC_DRAW);
    
}



- (void)loadTempShader// fbo
{
    NSString *vertexShaderString = @"#version 300 es \n"
    "layout (location = 0 ) in vec4 position; \n"
    "layout (location = 1 ) in vec2 a_texcoord_l; \n"
    "layout (location = 2 ) in vec2 a_texcoord_r; \n"
    "out vec2 outColor_l; \n"
    "out vec2 outColor_r; \n"
    "void main() { \n"
    "gl_Position = position; \n"
    "outColor_l = a_texcoord_l; \n"
    "outColor_r = a_texcoord_r; \n"
    "}";
    
    NSString *fragmentShaderString = @"#version 300 es\n"
    "precision mediump float; \n"
    "in vec2 outColor_l; \n"
    "in vec2 outColor_r; \n"
    "uniform sampler2D inputImageTexture;\n"
    "layout(location = 0) out vec4 v_color2; \n"
    "layout(location = 1) out vec4 v_color3; \n"
    "void main() {\n"
    "v_color2 = texture(inputImageTexture, outColor_l); \n"
    "v_color3 = texture(inputImageTexture, outColor_r); \n"
    "}";
    
    GLint vertexShader = [self compileShaderWithString:vertexShaderString withType:GL_VERTEX_SHADER];
    GLint fragmentShader = [self compileShaderWithString:fragmentShaderString withType:GL_FRAGMENT_SHADER];
    
    tempProgram = glCreateProgram();
    glAttachShader(tempProgram, vertexShader);
    glAttachShader(tempProgram, fragmentShader);
    
    
    glLinkProgram(tempProgram);
    GLint linkStatus;
    glGetProgramiv(tempProgram, GL_LINK_STATUS, &linkStatus);
    if (linkStatus == GL_FALSE) {
        GLint length;
        glGetProgramiv(tempProgram, GL_INFO_LOG_LENGTH, &length);
        if (length > 0) {
            GLchar *infolog = malloc(sizeof(GLchar) * length);
            glGetProgramInfoLog(tempProgram, length, NULL, infolog);
            fprintf(stderr, "link error = %s", infolog);
            if (infolog) {
                free(infolog);
            }
        }
    }
    glValidateProgram(tempProgram);
    
    glUseProgram(tempProgram);
    ViewAttributes[TEMP_ATTRIBUTE_INPUT_TEXTURE_COORDINATE_L]  = glGetAttribLocation(tempProgram, "a_texcoord_l");
    NSLog(@"TEMP_ATTRIBUTE_INPUT_TEXTURE_COORDINATE_L:%d",ViewAttributes[TEMP_ATTRIBUTE_INPUT_TEXTURE_COORDINATE_L]);
    
    ViewAttributes[TEMP_ATTRIBUTE_INPUT_TEXTURE_COORDINATE_R]  = glGetAttribLocation(tempProgram, "a_texcoord_r");
    NSLog(@"TEMP_ATTRIBUTE_INPUT_TEXTURE_COORDINATE_R:%d",ViewAttributes[TEMP_ATTRIBUTE_INPUT_TEXTURE_COORDINATE_R]);
    
    ViewAttributes[TEMP_ATTRIBUTE_POSITION] = glGetAttribLocation(tempProgram, "position");
    NSLog(@"TEMP_ATTRIBUTE_POSITION:%d",ViewAttributes[TEMP_ATTRIBUTE_POSITION]);
    
    ViewUniforms[TEMP_UNIFORM_INPUT_IMAGE_TEXTURE] = glGetUniformLocation(tempProgram, "inputImageTexture");
    NSLog(@"TEMP_UNIFORM_INPUT_IMAGE_TEXTURE:%d",ViewAttributes[TEMP_UNIFORM_INPUT_IMAGE_TEXTURE]);
    
    
    
    glEnableVertexAttribArray(ViewAttributes[TEMP_ATTRIBUTE_POSITION]);
    glEnableVertexAttribArray(ViewAttributes[TEMP_ATTRIBUTE_INPUT_TEXTURE_COORDINATE_L]);
    glEnableVertexAttribArray(ViewAttributes[TEMP_ATTRIBUTE_INPUT_TEXTURE_COORDINATE_R]);
    
}

- (void)loadShaders
{
    /*
     //暂时按 得到左右2个纹理后，进行偶奇列排列
     NSString *vertexShaderString = @""
     "attribute vec4 position; \n"
     "attribute vec2 inputTextureCoordinate; \n"
     "varying lowp vec2 textureCoordinate; \n"
     "void main() { \n"
     "textureCoordinate = inputTextureCoordinate;\n"
     "gl_Position = position;\n}";
     
     NSString *fragmentShaderString = @""
     "varying lowp vec2 textureCoordinate;\n"
     "uniform sampler2D inputImageTexture;\n"
     "void main() {\n"
     "gl_FragColor = texture2D(inputImageTexture, textureCoordinate);\n}";*/
    
    NSString *vertexShaderString = @"#version 300 es \n"
    "layout (location = 0 ) in vec4 position; \n"
    "layout (location = 1 ) in vec2 a_texcoord; \n"
    "out vec2 outColor; \n"
    "void main() { \n"
    "gl_Position = position; \n"
    "outColor = a_texcoord; \n}";
    
    NSString *fragmentShaderString = @"#version 300 es  \n"
    "precision mediump float;                           \n"
    "in vec2 outColor;                                  \n"
    "uniform sampler2D inputImageTextureL;              \n"
    "uniform sampler2D inputImageTextureR;              \n"
    "layout(location = 0) out vec4 v_color;             \n"
    "void main() {                                      \n"
    "highp vec4 pixelLeft  = texture(inputImageTextureL, outColor);         \n"
    "highp vec4 pixelRight = texture(inputImageTextureR, outColor);         \n"
    "highp vec2 p = vec2(floor(gl_FragCoord.x), floor(gl_FragCoord.y));     \n"
    "if( mod(p.x,2.0) == 0.0 ){                     \n"
    "   v_color = pixelLeft;                        \n"
    "}else{                                         \n"
    "   v_color = pixelRight;                       \n"
    "}                                              \n"
    "}                                              \n";
    GLint vertexShader =   [self compileShaderWithString:vertexShaderString   withType:GL_VERTEX_SHADER];
    GLint fragmentShader = [self compileShaderWithString:fragmentShaderString withType:GL_FRAGMENT_SHADER];
    
    program = glCreateProgram();
    glAttachShader(program, vertexShader);
    glAttachShader(program, fragmentShader);
    
    
    glLinkProgram(program);
    GLint linkStatus;
    glGetProgramiv(program, GL_LINK_STATUS, &linkStatus);
    if (linkStatus == GL_FALSE) {
        GLint length;
        glGetProgramiv(program, GL_INFO_LOG_LENGTH, &length);
        if (length > 0) {
            GLchar *infolog = malloc(sizeof(GLchar) * length);
            glGetProgramInfoLog(program, length, NULL, infolog);
            fprintf(stderr, "link error = %s", infolog);
            if (infolog) {
                free(infolog);
            }
        }
    }
    glValidateProgram(program);
    
    glUseProgram(program);
    
    ViewAttributes[ATTRIBUTE_INPUT_TEXTURE_COORDINATE]  = glGetAttribLocation(program, "a_texcoord");
    NSLog(@"ATTRIBUTE_INPUT_TEXTURE_COORDINATE:%d",ViewAttributes[ATTRIBUTE_INPUT_TEXTURE_COORDINATE]);
    
    ViewAttributes[ATTRIBUTE_POSITION] = glGetAttribLocation(program, "position");
    NSLog(@"ATTRIBUTE_POSITION:%d",ViewAttributes[ATTRIBUTE_POSITION]);
    
    ViewUniforms[UNIFORM_INPUT_IMAGE_TEXTURE_L] = glGetUniformLocation(program, "inputImageTextureL");
    NSLog(@"UNIFORM_INPUT_IMAGE_TEXTURE_L:%d",ViewAttributes[UNIFORM_INPUT_IMAGE_TEXTURE_L]);
    
    ViewUniforms[UNIFORM_INPUT_IMAGE_TEXTURE_R] = glGetUniformLocation(program, "inputImageTextureR");
    NSLog(@"UNIFORM_INPUT_IMAGE_TEXTURE_R:%d",ViewAttributes[UNIFORM_INPUT_IMAGE_TEXTURE_R]);
    
    glEnableVertexAttribArray(ViewAttributes[ATTRIBUTE_POSITION]);
    glEnableVertexAttribArray(ViewAttributes[ATTRIBUTE_INPUT_TEXTURE_COORDINATE]);
    
}

- (GLuint)compileShaderWithString:(NSString *)content withType:(GLenum)type {
    GLuint shader;
    const char *shaderString = content.UTF8String;
    shader = glCreateShader(type);
    glShaderSource(shader, 1, &shaderString, NULL);
    glCompileShader(shader);
    
    GLint status;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
    if (status == GL_FALSE) {
        GLint length;
        glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &length);
        if (length > 0) {
            GLchar *infolog = malloc(sizeof(GLchar) * length);
            glGetShaderInfoLog(shader, length, NULL, infolog);
            fprintf(stderr, "compile error = %s", infolog);
            if (infolog) {
                free(infolog);
            }
        }
    }
    return shader;
}

const GLenum mrt[2] = {GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1};

-(void)renderFBO{
    
    glBindFramebuffer(GL_FRAMEBUFFER, _fbo);
    glClear(GL_COLOR_BUFFER_BIT);
    glDrawBuffers(2,mrt);
    
    glViewport(0, 0,  _imageWidth, _imageHeight);
    glClear(GL_COLOR_BUFFER_BIT);
    glClearColor(0.0f, 1.0f, 1.0f, 1.0f);
    glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);
    glUseProgram(tempProgram);
    
    
    glUniform1i(ViewUniforms[TEMP_UNIFORM_INPUT_IMAGE_TEXTURE], 0);
    glVertexAttribPointer(ViewAttributes[TEMP_ATTRIBUTE_POSITION], 4, GL_FLOAT, GL_FALSE, sizeof(CustomVertex), 0);
    glVertexAttribPointer(ViewAttributes[TEMP_ATTRIBUTE_INPUT_TEXTURE_COORDINATE_L], 2, GL_FLOAT, GL_FALSE, sizeof(CustomVertex), (GLvoid *)(sizeof(float) * 4));
    glVertexAttribPointer(ViewAttributes[TEMP_ATTRIBUTE_INPUT_TEXTURE_COORDINATE_R], 2, GL_FLOAT, GL_FALSE, sizeof(CustomVertex), (GLvoid *)(sizeof(float) * 6));
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    //glBindFramebuffer ( GL_DRAW_FRAMEBUFFER, _framebuffer );
    
}



- (void)render{
    
    [self renderFBO];
    
    //[((GLKView *) self) bindDrawable];
    glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
    glUseProgram(program);
    
    glClearColor(1.0, 0.0, 0.0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);
    glBindBuffer(GL_ARRAY_BUFFER, vertexToScreenBuffer);
    
    glViewport(0, 0, _backingWidth, _backingHeight);
    
    //glBindTexture(GL_TEXTURE_2D, _imageTexture);
    glUniform1i(ViewUniforms[UNIFORM_INPUT_IMAGE_TEXTURE_L], 1);
    glUniform1i(ViewUniforms[UNIFORM_INPUT_IMAGE_TEXTURE_R], 2);
    
    glVertexAttribPointer(ViewAttributes[ATTRIBUTE_POSITION], 4, GL_FLOAT, GL_FALSE, sizeof(CustomVertexToScreen), 0);
    glVertexAttribPointer(ViewAttributes[ATTRIBUTE_INPUT_TEXTURE_COORDINATE], 2, GL_FLOAT, GL_FALSE, sizeof(CustomVertexToScreen), (GLvoid *)(sizeof(float) * 4));
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    glBindRenderbuffer(GL_RENDERBUFFER, _renderbuffer);
    [glContext presentRenderbuffer:GL_RENDERBUFFER];
    
    
}


- (void)setImage:(UIImage *)image{
    _image = image;
    
    [self update];
}

@end
