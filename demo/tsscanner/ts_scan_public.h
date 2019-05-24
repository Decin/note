//
//  ts_scan_public.h
//  DTV
//
//  Created by NS on 2018/5/18.
//  Copyright © 2018年 SFT. All rights reserved.
//

#ifndef ts_scan_public_h
#define ts_scan_public_h

#ifndef _DVBPSI_DVBPSI_H_
#include "dvbpsi.h"
#endif

#define EitSegmentOrderCallback 1       // EitSegmentOrderCallback为1时, 按照segment返回且不存储
                                        //
                                        // EitSegmentOrderCallback为0时, 按照
                                        // eits       节目,              节目,           节目
                                        //              |                |               |
                                        // sub_eit 0x4E,0x50,0x51  0x4E,0x50,0x51     0x4E,0x50,0x51
                                        // 且最终存储在ts_epg_t结构中

#define TotCallbackCurrentEitUTCTime 1


/*****************************************************************************
 * General typdefs
 *****************************************************************************/
typedef int vlc_bool_t;
#define VLC_FALSE 0
#define VLC_TRUE  1

typedef int64_t mtime_t;

#pragma mark - PAT | PMT | SDT
/*****************************************************************************
 * TS stream structures
 *----------------------------------------------------------------------------
 * PAT pid=0
 * - refers to N PMT's with pids known PAT
 *  PMT 0 pid=X stream_type
 *  PMT 1 pid=Y stream_type
 *  PMT 2 pid=Z stream_type
 *  - a PMT refers to N program_streams with pids known from PMT
 *   PID A type audio
 *   PID B type audio
 *   PID C type audio .. etc
 *   PID D type video
 *   PID E type teletext
 *****************************************************************************/

typedef struct
{
    dvbpsi_t            *handle;
    
    int                 i_pat_version;
    int                 i_ts_id;
    
    vlc_bool_t          b_seen;
} ts_pat_t;

typedef struct
{
    dvbpsi_t            *handle;
    
    int                 i_sdt_version;
    int                 i_ts_id;
    
    vlc_bool_t          b_seen;
} ts_sdt_t;

typedef struct ts_pid_s
{
    int         i_pid;
    
    vlc_bool_t  b_seen;
    int         i_cc;   /* countinuity counter */
    
    vlc_bool_t  b_pcr;  /* this PID is the PCR_PID */
    mtime_t     i_pcr;  /* last know PCR value */
} ts_pid_t;


typedef struct
{
    uint32_t i_max_bitrate;
} max_bitrate_descriptor_t;

typedef struct
{
    int b_external_clock_ref;
    uint8_t i_clock_accuracy_integer;
    uint8_t i_clock_accuracy_exponent;
} system_clock_descriptor_t;

typedef struct
{
    uint8_t i_component_tag;
} stream_identifier_descriptor_t;

typedef struct
{
    uint8_t i_iso6392_language_code[3];
    uint8_t i_subtitling_type;
    uint16_t i_composition_page_id;
    uint16_t i_ancillary_page_id;
} one_subtitle_t;

typedef struct
{
    one_subtitle_t *subtitles;
    unsigned char count;
} subtitle_descriptor_t;

typedef struct
{
    uint8_t *data;
    unsigned char length;
} unknown_descriptor_t;

typedef union
{
    max_bitrate_descriptor_t max_bitrate;
    system_clock_descriptor_t system_clock;
    stream_identifier_descriptor_t stream_identifier;
    subtitle_descriptor_t subtitle;
    unknown_descriptor_t unknown;
} descriptor_info_t;

typedef enum
{
    max_bitrate,
    system_clock,
    stream_identifier,
    subtitle,
    unknown
} descriptor_type_t;

struct descriptor_s;
typedef struct descriptor_s descriptor_t;

struct descriptor_s
{
    unsigned char i_tag;
    descriptor_type_t type;
    descriptor_info_t info;
    
    descriptor_t *next;
};

struct descriptor_es_s;
typedef struct descriptor_es_s descriptor_es_t;

// A PMT record might have many ES descriptors, where each has a LL of normal
// descriptors.
struct descriptor_es_s
{
    uint8_t i_type; /*!< stream_type */
    char *type_name;
    uint16_t i_pid; /*!< elementary_PID */
    
    descriptor_t *next_child;
    descriptor_es_t *next_sibling;
};

typedef struct ts_pmt_s
{
    dvbpsi_t    *handle;
    
    int                 i_number; /* i_number = 0 is actually a NIT */
    int                 i_pmt_version;
    vlc_bool_t          b_seen;

    uint8_t             *c_provider_name;
    uint8_t             i_provider_name_length;
    
    uint8_t             *c_program_name;
    uint8_t             i_name_length;
    
    int                 av_pids_sum;        ///< es pid sum
    uint16_t            av_pids[256];       /* FIXME: 临时用256大小 */
    int                 v_pids_sum;        ///< video pid sum
    uint16_t            v_pids[256];
    int                 a_pids_sum;        ///< audio pid sum
    uint16_t            a_pids[256];
    int                 extra_pids_sum;     ///< extra pid sum
    uint16_t            extra_pids[256];

    vlc_bool_t          b_scrambling;
    vlc_bool_t          b_radio;
    
    
    descriptor_t *pmt_descriptor;
    descriptor_es_t *pmt_es_descriptor;
    
    ts_pid_t            *pid_pmt;
    ts_pid_t            *pid_pcr;
    
    
    struct ts_pmt_s     *next;
} ts_pmt_t;


typedef struct ts_pmt_array_s
{
    int         i_pmt_sum;
    int         i_pmt_parsed;
    int         *i_pids;
    
    vlc_bool_t  b_seen;

    ts_pmt_t    *first_pmt;
} ts_pmt_array_t;

#pragma mark - TOT/TDT

/**
 * tot/tdt 有部分码流, 间隔时间可能会长到5秒, 甚至30s, 可从0x4e的eit表中取出当天, utc_time_0x4e为通过0x4e表生成
 */
typedef struct ts_tot_s {
    dvbpsi_t *           handle;
    
    int64_t utc_time_0x4e;  ///<  0x4e表的时间, 不为0, 此时时通过0x4e表生成, utc_time, offset时间为0

    /* FIXME: 部分码流utc_time_0x4e和tot的utc_time时间不是同一天的问题 */
    int64_t utc_time;       ///<  >>24 MJD  >>16 UTC
    int64_t offset;         ///< tiemzone, 单位秒, +-
} ts_tot_t;

#pragma mark - EPG
typedef struct ts_event_s {
    
    int16_t     event_id;
    
    // int MJD = (int)(event->startDate >> 24);
    // int UTC = (int)(event->startDate & 0xFFFFFF);
    int64_t     start_date;
    int32_t     duration;                   ///< 时间为秒
    
    uint8_t     code[3];                    ///< 语言代码, 如tha, eng
    char *      event_name;
    int         event_name_length;
    char *      event_decription;
    int         event_decription_length;

    struct ts_event_s *next;
} ts_event_t;


/**
 每个表的全部事件
 */
typedef struct ts_events_s {
    
    int                 i_event_sum;
    
    ts_event_t *        first_event;
} ts_events_t;


/**
 一个节目下的各个子表(0x4E, 0x50, 0x51...)
 */
typedef struct ts_sub_eit_s {
    int                 i_eit_version;
    int                 i_table_id;     // 0x4E, 0x50, 0x51...
    int                 i_extension;
    
    int64_t             tot_utc_time;      /* FIXME: 临时使用, gen */
    int                 tot_offset;        /* FIXME: 临时使用 */

    
    ts_events_t         events;
    
    struct ts_sub_eit_s *next;
} ts_sub_eit_t;

/**
 ts_eits_t 表 一个节目(i_extension), 存储多个表(0x4E, 0x50, 0x51...)
 */
typedef struct ts_eits_s {
    //    dvbpsi_t            *handle;
    
    int                 i_extension;   // program number
    int                 i_eit_sum;     // 代表同一节目下的全部子表
    vlc_bool_t          b_seen;        // 如上(i_eit_sum), 节目下的子表/0x4E, 0x50, 0x51...是否已经解析全
    
    
    ts_sub_eit_t *      first_eit;     // 包括表 0x4E, 0x50, 0x51...
    
    int64_t             tot_utc_time;      //  >>24 MJD  >>16 UTC
    
    struct ts_eits_s *  next;
} ts_eits_t;


typedef void (*scan_epg_complete_callback)(ts_eits_t *eits, void *p_data);

typedef void (*scan_epg_table_callback)(ts_sub_eit_t *eit, void *p_data);
typedef void (*scan_epg_segment_callback)(ts_sub_eit_t *eit, void *p_data);
typedef void (*scan_epg_tot_callback)(ts_tot_t *tot, void *p_data);

/**
 每个channel的epg(很多EIT的集合)
 */
typedef struct ts_epg_s {
    dvbpsi_t *           handle;
    
    int                  *arr_need_parse_tid;       ///< 需要解析的EIT表, 0x4E, 0x50, 0x51... 等
    int                  i_need_parse_tid_sum;

    ts_eits_t *          first_eits;                ///< 节目下的eit

    scan_epg_table_callback         pf_epg_table_callback;
    scan_epg_segment_callback       pf_epg_segment_callback;
    scan_epg_tot_callback           pf_tot_callback;
} ts_epg_t;

#pragma mark - Main
typedef struct
{
    ts_pat_t            pat;
    ts_pid_t            pid[0x1FFF + 1];    // 记录是否已存储该packet
    
    // 新增
    ts_pmt_array_t      pmts;
    ts_sdt_t            sdt;
    
    vlc_bool_t          b_program_seen;     // 各节目解析是否完成
    
    ts_epg_t            epg;             // epg
    vlc_bool_t          b_eits_seen;     // 各节目eit解析是否完成
    
    /////// modified /////////
    ts_tot_t            tot;
    vlc_bool_t          b_tot_seen;     // tot解析是否完成

} ts_stream_t;

typedef enum {
    scan_type_program       = 1 << 0,
    scan_type_eit           = 1 << 1,
//    scan_type_program,
} scan_type_t;

typedef enum {
    scan_program_packet_pat        = 1 << 0,
    scan_program_packet_pmt        = 1 << 1,
    scan_program_packet_sdt        = 1 << 2,
} scan_program_packet_type_t;

typedef struct scan_state_s scan_state_t;
typedef void (*scan_complete_t)(scan_state_t *state, void *p_data);

typedef struct scan_state_s
{
    ts_stream_t *p_stream;
    
    int dtvmode;
    int frequency;
    
    int found;          // 1: 已经找到  0: 未找到  -1: 中断  
    
    /* 扫描标识 */
    scan_type_t scan_type;
    scan_program_packet_type_t scan_program_packet_type;
    scan_program_packet_type_t scan_program_packet_done;

    int *arr_useful_service_ids;        ///< eit 单独扫描时使用
    int i_useful_service_ids_length;        ///< eit 单独扫描时使用

    scan_complete_t scan_complete_block;
    scan_epg_complete_callback pf_epg_complete_callback;

    void *private_data;
    
} scan_state_t;


#pragma mark - Interface
/**
 put buffer into queue and wait to scan

 @param tsbuf buffer
 @param bufsize buffer size
 @return 0 is success, other is fail.
 */
extern int stream_entry( void *tsbuf, unsigned int bufsize );


/**
 scan program psi(pat, pmt, sdt)

 @param dtvmode dtvmode
 @param frequency frequency
 @param pf_complete_cb definde complete action
 @param p_data private data
 @return 0 is success, other is fail: -1 abnormal stop, -2 timeout.
 */
extern int scan_program( int dtvmode, int frequency, bool block, scan_complete_t pf_complete_cb, void *p_data );

/**
 scan eit
 always use when program is playing

 @param epg_table_callback return a table(32 segment) one by one
 @param epg_tot_callback return tot utctime
 @param p_data user private data
 @return 0 is success, other is fail: -1 abnormal stop, -2 timeout.
 */
extern int scan_epg_table( scan_epg_table_callback epg_table_callback, scan_epg_tot_callback epg_tot_callback, void *p_data );

#if EitSegmentOrderCallback
/**
 scan eit
 always use when program is playing

 @param epg_segment_callback return segment(8 sections) one by one
 @param epg_tot_callback return tot utctime
 @param p_data user private data
 @return 0 is success, other is fail: -1 abnormal stop, -2 timeout.
 */
extern int scan_epg_segment( scan_epg_segment_callback epg_segment_callback, scan_epg_tot_callback epg_tot_callback, void *p_data );
#endif



/**
 stop scan program or epg
 */
extern int stop_scan(void);


#define kScanTimeOut 60.0

#endif /* ts_scan_public_h */
