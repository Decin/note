# vlckit

## add record function
```
int libvlc_video_toggle_record( libvlc_media_player_t *p_mi,const char *psz_filepath )
{
    input_thread_t *p_input = libvlc_get_input_thread( p_mi );
    if(p_input == NULL)
    return -1;
    var_Create( p_input, "input-record-path", VLC_VAR_STRING );
    var_SetString( p_input, "input-record-path", psz_filepath );
    var_ToggleBool( p_input, "record");
    vlc_object_release(p_input);
    return 0;
}
```
------------where?------------
like as libvlc_video_take_snapshot interface
1.libvlc.sym(vlc/lib/libvlc.sym) add libvlc_video_toggle_record
2.video.c(vlc/lib/video.c) add upon function
3.libvlc_media_player.h(vlc/include/vlc/libvlc_media_player.h) add int libvlc_video_toggle_record( libvlc_media_player_t *p_mi,const char *psz_filepath )


## add set program number
```
int libvlc_video_change_program ( libvlc_media_player_t *p_mi,
int p_num )
{
input_thread_t *p_input = libvlc_get_input_thread( p_mi );
if(p_input == NULL)
return -1;
var_Create( p_input, "program", VLC_VAR_INTEGER | VLC_VAR_DOINHERIT );
var_SetInteger( p_input, "program", p_num );
vlc_object_release(p_input);
return 0;
}
```
------------where?------------
like as libvlc_video_take_snapshot interface


## update record file name
vlc/include/vlc_input.h
`
#define INPUT_RECORD_PREFIX
`


## add progress display
MobileVLCKit.xcodeproj -->  VLCMediaplayer.m --> HandleMediaInstanceStateChanged
```
if (newState == VLCMediaPlayerStateBuffering) {
[[VLCEventManager sharedManager] callOnMainThreadDelegateOfObject:(__bridge id)(self)
withDelegateMethod:@selector(mediaPlayerStateChanged:)
withNotificationName:VLCMediaPlayerStateChanged
userInfo:@{VLCPlayerStateBufferingProgress : @(event->u.media_player_buffering.new_cache / 100.0)}];
return;
}
```

MobileVLCKit.xcodeproj -->  VLCEventManager --> - callDelegateOfObjectAndSendNotificationWithArgs:

change
```
method(delegate, targetSelector, [NSNotification notificationWithName:notificationName object:target]);
```
to
```
method(delegate, targetSelector, [NSNotification notificationWithName:notificationName object:target userInfo:message.object]);
```

add under method and definition
```
- (void)callOnMainThreadDelegateOfObject:(id)aTarget withDelegateMethod:(SEL)aSelector withNotificationName:(NSString *)aNotificationName userInfo:(NSDictionary *)userInfo {
/* Don't send on main thread before this gets sorted out */
@autoreleasepool {
message_t *message = [message_t new];
message.sel = aSelector;
message.target = aTarget;
message.name = aNotificationName;
message.type = VLCNotification;
message.object = userInfo;

pthread_mutex_lock(&_queueLock);
[_messageQueue insertObject:message atIndex:0];
pthread_cond_signal(&_signalData);
pthread_mutex_unlock(&_queueLock);
}
}
```
```
extern NSString *const VLCPlayerStateBufferingProgress;

NSString *const VLCPlayerStateBufferingProgress = @"VLCPlayerStateBufferingProgress";
```

## fix force play and 
libvlc/vlc/src/input/decoder.c
#define DECODER_BOGUS_VIDEO_DELAY                ((mtime_t)(DEFAULT_PTS_DELAY * 30))

## subtitle
"freetype-color"
"freetype-background-opacity"
"freetype-background-color"
"freetype-outline-thickness"
...

## epg osd
```
int libvlc_video_toggle_epg( libvlc_media_player_t *p_mi)
{
    input_thread_t *p_input = libvlc_get_input_thread( p_mi );
    if(p_input == NULL) return -1;

    /* Apply to current video outputs (if any) */
    size_t n;
    vout_thread_t **pp_vouts = GetVouts (p_mi, &n);
    for (size_t i = 0; i < n; i++)
    {
    vout_OSDEpg( pp_vouts[i], input_GetItem( p_input ) );
    }
    free (pp_vouts);

    return 0;
}
```



