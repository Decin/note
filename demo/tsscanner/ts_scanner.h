#ifndef ts_scanner_h
#define ts_scanner_h

#ifndef _DVBPSI_DVBPSI_H_
#include "dvbpsi.h"
#endif

#include "ts_scan_public.h"

#define SYSTEM_CLOCK_DR 0x0B
#define MAX_BITRATE_DR 0x0E
#define STREAM_IDENTIFIER_DR 0x52
#define SUBTITLING_DR 0x59


/**
 预处理, 创建handle等
 */
typedef int (*pre_callback_t)(void *state);


/**
 处理, 处理pmt, sdt等

 paket is a ts paket, state is scan_state_t
 */
typedef int (*process_callback_t)(void *paket, void *state);

/**
 扫描结束, 释放handle等
 */
typedef void (*post_callback_t)(void *state);


/**
 check whether scan action is need to stop
 
 @return return 1 is scan success, -1 interrupt, 0 epg/program is not yet
 */
//typedef int (*continuation_check_callback_t)(void *state, void *p_data);
typedef int (*continuation_check_callback_t)(void *state, void *p_data, bool force);


/**
 扫描ts流

 @return return 0 is success
 */
//extern int scan_stream(pre_callback_t pre_callback,
//                       post_callback_t post_callback,
//                       continuation_check_callback_t continuation_callback,
//                       void *state);

extern int scan_stream(pre_callback_t pre_callback,
                       process_callback_t process_callback,
                       post_callback_t post_callback,
                       continuation_check_callback_t continuation_callback,
                       void *state,
                       int packet_count,
                       void *p_data);

#endif /* ts_scanner_h */
