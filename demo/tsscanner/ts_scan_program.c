
#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <math.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>
#include <time.h>
#include <sys/time.h>

#include "dvbpsi.h"
#include "pat.h"

#include "psi.h"
#include "descriptor.h"
#include "pmt.h"
#include "dr.h"
#include "sdt.h"
#include "demux.h"
#include "eit.h"
#include "tot.h"

#include "ts_scanner.h"
#include "ts_scan_program.h"
#include "ts_scan_program_extend.h"

#if defined(__APPLE__)
#include <CoreFoundation/CFDate.h>
#elif defined(__ANDRIOD__)

#endif

#define TS_PID_PAT 0x0000
#define TS_PID_SDT 0x0011
#define TS_PID_EIT 0x0012
#define TS_PID_TOT 0x0014

#define TS_TABLEID_SDT 0x42

#define TS_TABLEID_TDT 0x70
#define TS_TABLEID_TOT 0x73

#define TS_TABLEID_EIT_CURRENTNEXT 0x4E
#define TS_TABLEID_EIT_CURRENTSTREAM_MIN 0x50
#define TS_TABLEID_EIT_CURRENTSTREAM_MAX 0x5F
#define TS_TABLEID_EIT_EXTRASTREAM_MIN 0x60
#define TS_TABLEID_EIT_EXTRASTREAM_MAX 0x6F


/*****************************************************************************
 * Local prototypes
 *****************************************************************************/
#pragma mark - Front declare
static void pmt_received(void* p_data, dvbpsi_pmt_t* p_pmt);
static void pat_received(void* p_data, dvbpsi_pat_t* p_pat);
static void eit_received(void* p_cb_data, dvbpsi_eit_t* p_new_eit, bool b_complete);


static char *get_type_name(uint8_t type);
static int set_descriptors(ts_pmt_t *pmt, descriptor_t **descriptor_ptr, dvbpsi_descriptor_t* p_descriptor);
static int set_descriptor_primitive(dvbpsi_descriptor_t* p_descriptor, descriptor_t *descriptor);

static void create_sdt_and_pmt(scan_state_t *state, dvbpsi_pat_program_t* p_program);
static ts_sub_eit_t *ts_sub_eit_new(dvbpsi_eit_t *p_new_eit);
static ts_eits_t *ts_eits_new(int i_extension);
static void set_eit_event(ts_sub_eit_t *des_eit, dvbpsi_eit_t *p_new_eit);
static bool check_eit_exit(ts_eits_t *des_eits, int eit_extension, int eit_table);
static ts_sub_eit_t *creat_and_set_eit(ts_eits_t *des_eits, dvbpsi_eit_t *p_new_eit);

static uint8_t get_tableid(uint8_t *packet);

static void dump_pmt_descriptors(void* p_zero, dvbpsi_descriptor_t* p_descriptor);
static void new_subtable(dvbpsi_t *p_dvbpsi, uint8_t i_table_id, uint16_t i_extension, void * p_zero);
static void message(dvbpsi_t *handle, const dvbpsi_msg_level_t level, const char* msg);

bool _is_stop = false;



void free_subeit(ts_sub_eit_t *sub_eit);
void free_event(ts_event_t *event);

#pragma mark - Print
static void message(dvbpsi_t *handle, const dvbpsi_msg_level_t level, const char* msg)
{
    switch(level)
    {
        case DVBPSI_MSG_ERROR: fprintf(stderr, "Error: "); break;
        case DVBPSI_MSG_WARN:  fprintf(stderr, "Warning: "); break;
        case DVBPSI_MSG_DEBUG: fprintf(stderr, "Debug: "); break;
        default: /* do nothing */
            return;
    }
    fprintf(stderr, "%s\n", msg);
}

#pragma mark - Receive Table
// Describes list of programs on channel.
static void pat_received( void* p_data, dvbpsi_pat_t* p_pat )
{
    dvbpsi_pat_program_t* p_program = p_pat->p_first_program;

    scan_state_t* scan_state = (scan_state_t *) p_data;
    ts_stream_t* p_stream = scan_state->p_stream;
    if (p_stream->pat.b_seen) {
        dvbpsi_pat_delete(p_pat);
        return;
    }
    
    p_stream->pat.i_pat_version = p_pat->i_version;
    p_stream->pat.i_ts_id = p_pat->i_ts_id;
    
    if (scan_state->scan_type & scan_type_program) {
        // create sdt handle, pmt and so on
        create_sdt_and_pmt( scan_state, p_program ); /* FIXME: sdt 和 pat 一起解析, 以免时间过长 */
    }

    p_stream->pat.b_seen = 1;
    scan_state->scan_program_packet_done |= scan_program_packet_pat;
    dvbpsi_pat_delete(p_pat);
}


static void pmt_received(void* p_data, dvbpsi_pmt_t* p_pmt)
{
    scan_state_t *state = (scan_state_t *)p_data;
    ts_stream_t *p_stream = state->p_stream;
    ts_pmt_array_t *pmts = &state->p_stream->pmts;
    
    if (p_stream->pmts.b_seen)  {
        dvbpsi_pmt_delete(p_pmt);
        return;
    }
    
    if ( p_stream->pmts.b_seen && p_stream->sdt.b_seen ) {
        p_stream->b_program_seen = true;
    }
    
    // find pmt with the same i_number
    ts_pmt_t *pmt = pmts->first_pmt;
    while ( pmt ) {
        if ( pmt->i_number == p_pmt->i_program_number && !pmt->b_seen) break;
        pmt = pmt->next;
    }
    if (pmt == NULL) return;
    printf("\n----------program_number: %d----------\n", p_pmt->i_program_number);
    
    
    // config pmt
    pmt->i_pmt_version = p_pmt->i_version;
    set_descriptors(pmt, &pmt->pmt_descriptor, p_pmt->p_first_descriptor);

    //    state->pmt_program_number = p_pmt->i_program_number;
    //    state->pmt_version        = p_pmt->i_version;
    //    state->pmt_pcr_pid        = p_pmt->i_pcr_pid;
    

    dvbpsi_pmt_es_t *p_es = p_pmt->p_first_es;
    descriptor_es_t **descriptor_es = &pmt->pmt_es_descriptor;
    *descriptor_es = NULL;
    
    descriptor_es_t *descriptor_es_temp;
    
    while(p_es) {
        
        descriptor_es_temp = (descriptor_es_t *)malloc(sizeof(descriptor_es_t));
        *descriptor_es = descriptor_es_temp;
        
        descriptor_es_temp->i_pid        = p_es->i_pid;
        descriptor_es_temp->i_type       = p_es->i_type;
        descriptor_es_temp->type_name    = get_type_name(p_es->i_type);
        
        uint8_t es_types[] = {/* 视频pid */0x01, 0x02, 0x1b, 0xea,
                              /* 音频pid */0x03, 0x04, 0x0f, 0x11, 0x80, 0x81, 0x06, 0x82, 0x83, 0x84, 0x85, 0x86, 0xa1, 0xa2};
        /* FIXME: 优化算法 */
        bool is_esxit = false;
        for (int i = 0; i < sizeof(es_types) / sizeof(uint8_t); i++) {
            // 是否是 音频 或 视频 type
            if (p_es->i_type == es_types[i]) {
                pmt->av_pids[pmt->av_pids_sum] = p_es->i_pid;
                pmt->av_pids_sum += 1;
                
                // 区分音频和视频, 前4个位视频es type
                if (i < 4) {
                    pmt->v_pids[pmt->v_pids_sum] = p_es->i_pid;
                    pmt->v_pids_sum += 1;
                }
                else {
                    pmt->a_pids[pmt->a_pids_sum] = p_es->i_pid;
                    pmt->a_pids_sum += 1;
                }
                
                is_esxit = true;
                break;
            }
        }
        if (!is_esxit) {
            pmt->extra_pids[pmt->extra_pids_sum] = p_es->i_pid;
            pmt->extra_pids_sum += 1;
        }
        
        
        descriptor_es_temp->next_sibling = NULL;
        
        set_descriptors(pmt, &descriptor_es_temp->next_child, p_es->p_first_descriptor);
        
        p_es = p_es->p_next;
        descriptor_es = &descriptor_es_temp->next_sibling;
    }
    
    pmt->b_radio = (pmt->v_pids_sum == 0 && pmt->a_pids_sum > 0);
    pmt->b_seen = 1;
    pmts->i_pmt_parsed++;
    printf("----------解析节目: %04d   已解析数量:%d \n", pmt->i_number, pmts->i_pmt_parsed);
    
    if (pmts->i_pmt_sum != 0 &&
        pmts->i_pmt_parsed == pmts->i_pmt_sum) {
        p_stream->pmts.b_seen = true;
        state->scan_program_packet_done |= scan_program_packet_pmt;
    }
    
    if (p_stream->pmts.b_seen && p_stream->sdt.b_seen) {
        state->scan_program_packet_done |= scan_program_packet_pmt;
        p_stream->b_program_seen = 1;
    }
    dvbpsi_pmt_delete(p_pmt);
}

/*****************************************************************************
 * DumpSDT
 *****************************************************************************/
static void sdt_received(void* p_zero, dvbpsi_sdt_t* p_sdt)
{
    scan_state_t *state = (scan_state_t *)p_zero;

    if ( state->p_stream->sdt.b_seen ) {
        dvbpsi_sdt_delete(p_sdt);
        return;
    }
    ts_pmt_array_t *pmts = &state->p_stream->pmts;
    if ( pmts->b_seen ) {
        state->p_stream->b_program_seen = 1;
    }
    
    dvbpsi_sdt_service_t* p_service = p_sdt->p_first_service;
    printf(  "\n");
    printf(  "New active SDT\n");
    printf(  "  ts_id : %d\n", p_sdt->i_extension);
    printf(  "  version_number : %d\n", p_sdt->i_version);
    printf(  "  network_id        : %d\n", p_sdt->i_network_id);
    printf(  "    | service_id \n");
    while(p_service) {
        printf("    | 0x%02x \n", p_service->i_service_id);
        
        ts_pmt_t *pmt = pmts->first_pmt;
        while (pmt) {
            if (pmt->i_number == p_service->i_service_id) {
                dump_pmt_descriptors(pmt, p_service->p_first_descriptor);
                break;
            }
            pmt = pmt->next;
        }
        
        p_service = p_service->p_next;
    }
    
    state->p_stream->sdt.b_seen = 1;
    state->scan_program_packet_done |= scan_program_packet_sdt;

    
    dvbpsi_sdt_delete(p_sdt);
}

static void eit_received(void *p_cb_data, dvbpsi_eit_t *p_new_eit, bool b_complete) {
    if (_is_stop) return;
    
    printf("%s-%s----------------------------节目 %d 的 %d EIT-\n", __FILE__, __FUNCTION__, p_new_eit->i_extension, p_new_eit->i_table_id);
    scan_state_t *state = (scan_state_t *)p_cb_data;
    
    if (b_complete) {
        ////////////// modified ////////////////
        if (state->scan_type == scan_type_eit) {
            
            ts_sub_eit_t *eit = NULL;
            
            // eits不存在, 则创建eits直接存储
            if (state->p_stream->epg.first_eits == NULL) {
                state->p_stream->epg.first_eits = ts_eits_new(p_new_eit->i_extension);
                eit = creat_and_set_eit(state->p_stream->epg.first_eits, p_new_eit);
            }
            // eits存在, 则先搜索eit表是否已存在于eits中,
            else {
                ts_eits_t *eits = state->p_stream->epg.first_eits;
                ts_eits_t *last_eits = state->p_stream->epg.first_eits;
                while (eits) {
                    if (eits->i_extension == p_new_eit->i_extension) {
                        
                        if (!check_eit_exit(eits, p_new_eit->i_extension, p_new_eit->i_table_id)) {
                            eit = creat_and_set_eit(eits, p_new_eit);
                        }
                        
                        break;
                    }
                    last_eits = eits;
                    eits = eits->next;
                }
                // 遍历了所有不存在当前节目的eits
                if (eits == NULL) {
                    last_eits->next = ts_eits_new(p_new_eit->i_extension);
                    
                    eit = creat_and_set_eit(last_eits->next, p_new_eit);
                }
            }
            
            if (eit) {
                if (state->p_stream->epg.pf_epg_table_callback)
                    state->p_stream->epg.pf_epg_table_callback(eit, state->private_data);
                
                // 防止tot/tdt来的太慢
                if (p_new_eit->i_table_id == 0x4e) {
                    if (p_new_eit->p_first_event) {
                        state->p_stream->tot.utc_time = p_new_eit->p_first_event->i_start_time;
                        state->p_stream->tot.utc_time_0x4e = p_new_eit->p_first_event->i_start_time;
                    }
                    
#if TotCallbackCurrentEitUTCTime
                    if (state->p_stream->epg.pf_tot_callback)
                        state->p_stream->epg.pf_tot_callback(&state->p_stream->tot, state->private_data);
#endif
                }
            }
        }
        dvbpsi_eit_delete(p_new_eit);
    }
    else {
        if ( p_new_eit->i_table_id >= 0x4e && p_new_eit->i_table_id <= 0x51 ) {
            
            // 防止tot/tdt来的太慢
            if (p_new_eit->i_table_id == 0x4e) {
                if (p_new_eit->p_first_event)
                    state->p_stream->tot.utc_time_0x4e = p_new_eit->p_first_event->i_start_time;
#if TotCallbackCurrentEitUTCTime
                if (state->p_stream->epg.pf_tot_callback)
                    state->p_stream->epg.pf_tot_callback(&state->p_stream->tot, state->private_data);
#endif
            }
            ts_sub_eit_t *eit_ = ts_sub_eit_new(p_new_eit);
            if (state->p_stream->epg.pf_epg_segment_callback) {
                state->p_stream->epg.pf_epg_segment_callback(eit_, state->private_data);
            }
            // 释放eit
            free_subeit(eit_);
        }
    }
}

static void eit_segment_received(void *p_cb_data, dvbpsi_eit_t *p_new_eit, bool b_complete) {
    if (_is_stop) return;
    
    printf("%s-%s----------------------------节目 %d 的 %d EIT-\n", __FILE__, __FUNCTION__, p_new_eit->i_extension, p_new_eit->i_table_id);
    scan_state_t *state = (scan_state_t *)p_cb_data;
    
    if (b_complete) {
        dvbpsi_eit_delete(p_new_eit);
    }
    else {
        if (p_new_eit->p_first_event == NULL) return;
        
        if ( p_new_eit->i_table_id >= 0x4e && p_new_eit->i_table_id <= 0x51 ) {
            
            // 防止tot/tdt来的太慢
            if (p_new_eit->i_table_id == 0x4e) {
                if (p_new_eit->p_first_event)
                    state->p_stream->tot.utc_time_0x4e = p_new_eit->p_first_event->i_start_time;
#if TotCallbackCurrentEitUTCTime
                if (state->p_stream->epg.pf_tot_callback)
                    state->p_stream->epg.pf_tot_callback(&state->p_stream->tot, state->private_data);
#endif
            }
            ts_sub_eit_t *eit_ = ts_sub_eit_new(p_new_eit);
            if (state->p_stream->epg.pf_epg_segment_callback)
                state->p_stream->epg.pf_epg_segment_callback(eit_, state->private_data);
            // 释放eit
            free_subeit(eit_);
        }
    }
}

static void tot_received(void* p_data, dvbpsi_tot_t* p_new_tot)
{
    if (_is_stop) return;
    
    scan_state_t *state = (scan_state_t *)p_data;
    state->p_stream->tot.utc_time = p_new_tot->i_utc_time;
    dvbpsi_descriptor_t *p_descriptor = p_new_tot->p_first_descriptor;
    while (p_descriptor) {
        if (p_descriptor->i_tag == 0x58) {
            
            /* FIXME: 多个时区问题 */
            // 可能有多个时区, 保存在local time offset loop, 每个共13个字节
            if (p_descriptor->i_length >= 13) {
                int8_t *p_data = (int8_t *)p_descriptor->p_data;
                int local_time_offset_bcd = ((*(p_data+4) << 8) | (*(p_data+5)));
                int local_time_offset_polarity = *(p_data+3) & 0x01;
                
#define OFFSET_FROM_BCD(v) ((((v) >> 4)&0xf)*10 + ((v)&0xf))
                int hou  = OFFSET_FROM_BCD(local_time_offset_bcd >>  8);
                int min  = OFFSET_FROM_BCD(local_time_offset_bcd      );
                state->p_stream->tot.offset = local_time_offset_polarity == 0 ? (hou * 60 + min) * 60 : - (hou * 60 + min) * 60;
#undef OFFSET_FROM_BCD
                
            }
            break;
        }
    }
#if TotCallbackCurrentEitUTCTime
    if (state->p_stream->epg.pf_tot_callback) {
        state->p_stream->epg.pf_tot_callback(&state->p_stream->tot, state->private_data);
    }
#endif
}

/*****************************************************************************
 * new_subtable
 *****************************************************************************/
static void new_subtable(dvbpsi_t *p_dvbpsi, uint8_t i_table_id, uint16_t i_extension,
                         void *p_zero)
{
    scan_state_t *state = (scan_state_t *)p_zero;
    
    if( i_table_id == TS_TABLEID_SDT )
    {
        if (!dvbpsi_sdt_attach(p_dvbpsi, i_table_id, i_extension, sdt_received, p_zero))
            fprintf(stderr, "Failed to attach SDT subdecoder\n");
    }
    else if ( i_table_id == TS_TABLEID_TDT || i_table_id == TS_TABLEID_TOT )
    {
        if (!dvbpsi_tot_attach(p_dvbpsi, i_table_id, i_extension, tot_received, p_zero))
            fprintf(stderr, "Failed to attach SDT subdecoder\n");
    }
    else if ( i_table_id == TS_TABLEID_EIT_CURRENTNEXT ||
             (i_table_id >= TS_TABLEID_EIT_CURRENTSTREAM_MIN && i_table_id <= TS_TABLEID_EIT_CURRENTSTREAM_MAX) )
    {
#if EitSegmentOrderCallback
        if (!dvbpsi_eit_attach(p_dvbpsi, i_table_id, i_extension, eit_segment_received, p_zero))
            fprintf(stderr, "Failed to attach EIT decoder i_table_id: %d i_extension: %d\n", i_table_id, i_extension);
#else
        if (!dvbpsi_eit_attach(p_dvbpsi, i_table_id, i_extension, eit_received, p_zero))
            fprintf(stderr, "Failed to attach EIT decoder i_table_id: %d i_extension: %d\n", i_table_id, i_extension);
#endif
    }
}

#pragma mark -
ts_eits_t *ts_eits_new(int i_extension) {
    ts_eits_t *eits = malloc(sizeof(ts_eits_t));
    memset(eits, 0, sizeof(ts_eits_t));
    eits->i_extension = i_extension;
    return eits;
}

ts_sub_eit_t *ts_sub_eit_new(dvbpsi_eit_t *p_new_eit) {
    ts_sub_eit_t *eit_ = malloc(sizeof(ts_sub_eit_t));
    memset(eit_, 0, sizeof(ts_sub_eit_t));
    
    eit_->i_eit_version = p_new_eit->i_version;
    eit_->i_table_id = p_new_eit->i_table_id;
    eit_->i_extension = p_new_eit->i_extension;
    
    set_eit_event(eit_, p_new_eit);
    
    return eit_;
}

static void create_sdt_and_pmt(scan_state_t *state, dvbpsi_pat_program_t* p_program) {
    ts_stream_t* p_stream = state->p_stream;
    
    // create sdt handle
    p_stream->sdt.handle = dvbpsi_new(&message, DVBPSI_MSG_DEBUG);
    dvbpsi_AttachDemux(p_stream->sdt.handle, new_subtable, state);
    
    while( p_program ) {
        // NIT
        if (p_program->i_number == 0) {
            p_program = p_program->p_next;
            continue;
        }
        
        ts_pmt_t *pmt = (ts_pmt_t *)calloc(1, sizeof(ts_pmt_t));
        if (pmt) {
            pmt->handle = dvbpsi_new(NULL, DVBPSI_MSG_DEBUG);
            if (!pmt->handle) {
                printf("%s-%s-dvbpsi_new 失败\n", __FILE__, __FUNCTION__);
                free(pmt);
                break;
            }
            
            pmt->i_number = p_program->i_number;
            pmt->pid_pmt = &p_stream->pid[p_program->i_pid];
            pmt->pid_pmt->i_pid = p_program->i_pid;
            
            
            if (!dvbpsi_pmt_attach(pmt->handle, p_program->i_number, pmt_received, state)) {
                fprintf(stderr, "dvbinfo: Failed to attach new pmt decoder\n");
                dvbpsi_delete(pmt->handle);
                free(pmt);
                break;
            }
            
            // save to tail
            if ( p_stream->pmts.first_pmt == NULL ) {
                p_stream->pmts.first_pmt = pmt;
            }
            else {
                ts_pmt_t *last_pmt = p_stream->pmts.first_pmt;
                while (last_pmt->next)
                    last_pmt = last_pmt->next;
                last_pmt->next = pmt;
            }
            
//            // insert start of list
//            pmt->next = p_stream->pmts.first_pmt;
//            p_stream->pmts.first_pmt = pmt;
            p_stream->pmts.i_pmt_sum++;
            
            
        } else
            fprintf(stderr, "dvbinfo: Failed create new PMT decoder\n");
        
        
        p_program = p_program->p_next;
    }
    
    
    // 存储所有pmt 的 pid
    //    int i_pids[p_stream->pmts.i_pmt_sum];
    int *i_pids = (int *)malloc(p_stream->pmts.i_pmt_sum * sizeof(int));
    memset(i_pids, p_stream->pmts.i_pmt_sum, sizeof(int));
    int i = 0;
    ts_pmt_t* p_pmt = p_stream->pmts.first_pmt;
    while (p_pmt) {
        i_pids[i] = p_pmt->pid_pmt->i_pid;
        printf("-----------%d", p_pmt->i_number);
        p_pmt = p_pmt->next;
        i++;
    }
    p_stream->pmts.i_pids = i_pids;
}

static bool check_eit_exit(ts_eits_t *des_eits, int eit_extension, int eit_table) {
    bool exit = false;
    ts_sub_eit_t *eit = des_eits->first_eit;
    while (eit) {
        if (eit->i_extension == eit_extension && eit->i_table_id == eit_table) {
            exit = true;
            break;
        }
        eit = eit->next;
    }
    return exit;
}

static ts_sub_eit_t *creat_and_set_eit(ts_eits_t *des_eits, dvbpsi_eit_t *p_new_eit) {
    // create eit and save
    ts_sub_eit_t *eit = ts_sub_eit_new(p_new_eit);
    if (des_eits->first_eit == NULL) {
        des_eits->first_eit = eit;
    }
    else {
        ts_sub_eit_t *last_eit = des_eits->first_eit;
        while (last_eit->next != NULL)
            last_eit = last_eit->next;
        last_eit->next = eit;
    }
    return eit;
}


static void set_eit_event(ts_sub_eit_t *des_eit, dvbpsi_eit_t *p_new_eit) {
    
    ts_events_t *events = &des_eit->events;
    dvbpsi_eit_event_t *event = p_new_eit->p_first_event;
    while (event) {
        
        ts_event_t *event_ = (ts_event_t *)malloc(sizeof(ts_event_t));
        memset(event_, 0, sizeof(ts_event_t));
        event_->duration = event->i_duration;
        event_->start_date = event->i_start_time;
        event_->event_id = event->i_event_id;
        
        // dvbpsi_descriptor_s's p_data
        // "eng" "\x16" "Gweler Radio Five Live UNos Da, rhaglen nesaf am 5.00 y bore. Radio Cymru joins Radio Five Live until 5.00am.\xad\xbe\x9ae{\x06ݺ\xa0\x17,\U00000081"
        // "eng" "\v" "Hywel A Nia \U00000013 traeon diddorol o Gymru a thu hwnt, chwerthin a chrio, sbort a bytheirio gyda Hywel a Nia. Quirky stories from around Wales and beyond, from the infuriating to the sublime, with Hywel and Nia."
        
        // iso_639_language_code_t    event_name_length    event_name    text_length    text
        
        // 获得short_event_descriptor
        dvbpsi_descriptor_t *p_descriptor = event->p_first_descriptor;
        while (p_descriptor) {
            if (p_descriptor->i_tag == 0x4D) break;
            p_descriptor = p_descriptor->p_next;
        }
        if (p_descriptor == NULL) p_descriptor = event->p_first_descriptor;
        
        if (p_descriptor) {
            int deslength = p_descriptor->i_length;
            
            memcpy(event_->code, p_descriptor->p_data, 3);
            
            int name_length = p_descriptor->p_data[3];
            char *name = malloc(sizeof(uint8_t) * name_length);
            memset(name, 0, name_length);
            memcpy(name, p_descriptor->p_data + 4, name_length);
            event_->event_name = name;
            event_->event_name_length = name_length;
            printf("%s-%s-----------------------------%s\n", __FILE__, __FUNCTION__, name);
            
            
            int text_length = p_descriptor->p_data[4 + name_length];
            char *text = malloc(sizeof(uint8_t) * text_length);
            memset(text, 0, text_length);
            memcpy(text, p_descriptor->p_data + 4 + name_length + 1, text_length);
            event_->event_decription = text;
            event_->event_decription_length = text_length;
            
            events->i_event_sum++;
        }
        
        if (events->first_event == NULL)
            events->first_event = event_;
        else {
            ts_event_t *last_event = events->first_event;
            while (last_event->next != NULL)
                last_event = last_event->next;
            last_event->next = event_;
        }
        event = event->p_next;
    }
}


static char *get_type_name(uint8_t type)
{
    switch (type)
    {
        case 0x00: return "Reserved";
        case 0x01: return "ISO/IEC 11172 Video";
        case 0x02: return "ISO/IEC 13818-2 Video";
        case 0x03: return "ISO/IEC 11172 Audio";
        case 0x04: return "ISO/IEC 13818-3 Audio";
        case 0x05: return "ISO/IEC 13818-1 Private Section";
        case 0x06: return "ISO/IEC 13818-1 Private PES data packets";
        case 0x07: return "ISO/IEC 13522 MHEG";
        case 0x08: return "ISO/IEC 13818-1 Annex A DSM CC";
        case 0x09: return "H222.1";
        case 0x0A: return "ISO/IEC 13818-6 type A";
        case 0x0B: return "ISO/IEC 13818-6 type B";
        case 0x0C: return "ISO/IEC 13818-6 type C";
        case 0x0D: return "ISO/IEC 13818-6 type D";
        case 0x0E: return "ISO/IEC 13818-1 auxillary";
            
        default:
            if (type < 0x80)
                return "ISO/IEC 13818-1 reserved";
            else
                return "User Private";
    }
}

static int set_descriptors(ts_pmt_t *pmt, descriptor_t **descriptor_ptr, dvbpsi_descriptor_t* p_descriptor)
{
    descriptor_t *descriptor;
    descriptor_t *last_descriptor = NULL;
    
    int i = 0;
    while(p_descriptor) {
        descriptor = (descriptor_t *)malloc(sizeof(descriptor_t));
        descriptor->i_tag = p_descriptor->i_tag;
        
        if (descriptor->i_tag == 0x09) {
            pmt->b_scrambling = true;
        }
        
        descriptor->next = NULL;
        
        if(set_descriptor_primitive(p_descriptor, descriptor) != 0)
            return -1;
        
        // Hook the first descriptor to the pointer-of-pointers that we were
        // given.
        if(*descriptor_ptr == NULL)
            *descriptor_ptr = descriptor;
        
        // Chain this descriptor to the last, if there is one.
        if(last_descriptor != NULL)
            last_descriptor->next = descriptor;
        
        last_descriptor = descriptor;
        
        p_descriptor = p_descriptor->p_next;
        i++;
    }
    
    return 0;
}

static int set_descriptor_primitive(dvbpsi_descriptor_t* p_descriptor, descriptor_t *descriptor)
{
    int a, i;
    
    dvbpsi_system_clock_dr_t *p_clock_descriptor;
    dvbpsi_max_bitrate_dr_t *bitrate_descriptor;
    dvbpsi_stream_identifier_dr_t *p_si_descriptor;
    dvbpsi_subtitling_dr_t *p_subtitle_descriptor;
    one_subtitle_t *subtitles_raw;
    
    switch (p_descriptor->i_tag)
    {
        case SYSTEM_CLOCK_DR:
            
            descriptor->type = system_clock;
            p_clock_descriptor = dvbpsi_DecodeSystemClockDr(p_descriptor);
            
            descriptor->info.system_clock.b_external_clock_ref      = p_clock_descriptor->b_external_clock_ref;
            descriptor->info.system_clock.i_clock_accuracy_integer  = p_clock_descriptor->i_clock_accuracy_integer;
            descriptor->info.system_clock.i_clock_accuracy_exponent = p_clock_descriptor->i_clock_accuracy_exponent;
            
            break;
            
        case MAX_BITRATE_DR:
            
            descriptor->type = max_bitrate;
            bitrate_descriptor = dvbpsi_DecodeMaxBitrateDr(p_descriptor);
            
            descriptor->info.max_bitrate.i_max_bitrate = bitrate_descriptor->i_max_bitrate;
            
            break;
            
        case STREAM_IDENTIFIER_DR:
            
            descriptor->type = stream_identifier;
            p_si_descriptor = dvbpsi_DecodeStreamIdentifierDr(p_descriptor);
            
            descriptor->info.stream_identifier.i_component_tag = p_si_descriptor->i_component_tag;
            
            break;
            
        case SUBTITLING_DR:
            
            descriptor->type = subtitle;
            p_subtitle_descriptor = dvbpsi_DecodeSubtitlingDr(p_descriptor);
            
            subtitles_raw = (one_subtitle_t *)calloc(p_subtitle_descriptor->i_subtitles_number,
                                                     sizeof(one_subtitle_t));
            
            descriptor->info.subtitle.subtitles = subtitles_raw;
            descriptor->info.subtitle.count     = p_subtitle_descriptor->i_subtitles_number;
            
            dvbpsi_subtitle_t subtitle;
            for (a = 0; a < p_subtitle_descriptor->i_subtitles_number; ++a)
            {
                subtitle = p_subtitle_descriptor->p_subtitle[a];
                
                subtitles_raw[a].i_iso6392_language_code[0] = subtitle.i_iso6392_language_code[0];
                subtitles_raw[a].i_iso6392_language_code[1] = subtitle.i_iso6392_language_code[1];
                subtitles_raw[a].i_iso6392_language_code[2] = subtitle.i_iso6392_language_code[2];
                subtitles_raw[a].i_subtitling_type          = subtitle.i_subtitling_type;
                subtitles_raw[a].i_composition_page_id      = subtitle.i_composition_page_id;
                subtitles_raw[a].i_ancillary_page_id        = subtitle.i_ancillary_page_id;
            }
            
            break;
            
        default:
            
            descriptor->type = unknown;
            descriptor->info.unknown.data = (uint8_t *)malloc(p_descriptor->i_length);
            
            i = 0;
            while(i < p_descriptor->i_length)
            {
                descriptor->info.unknown.data[i] = p_descriptor->p_data[i];
                i++;
            }
            
            descriptor->info.unknown.length = p_descriptor->i_length;
    }
    
    return 0;
}

#pragma mark - Callback
int pre_call(void *state_)
{
    scan_state_t *state = (scan_state_t *)state_;
    ts_stream_t *p_stream = ((scan_state_t *)state_)->p_stream;

    if ( state->scan_type == scan_type_program ) {
        if (state->scan_program_packet_type & scan_program_packet_pat) {
            p_stream->pat.handle = dvbpsi_new(&message, DVBPSI_MSG_DEBUG);
            dvbpsi_pat_attach(p_stream->pat.handle, pat_received, state);
        }
    }
    else if ( state->scan_type == scan_type_eit ) {
        
        p_stream->tot.handle = dvbpsi_new(&message, DVBPSI_MSG_DEBUG);
        dvbpsi_AttachDemux(p_stream->tot.handle, new_subtable, state);
        
        p_stream->epg.handle = dvbpsi_new(&message, DVBPSI_MSG_DEBUG);
        dvbpsi_AttachDemux(p_stream->epg.handle, new_subtable, state);

#if EitSegmentOrderCallback
        p_stream->epg.handle->b_segment_dump = true;
#else
        
#endif
    }

    return 0;
}

int process_call(void *packet, void *state_)
{
    scan_state_t *state = (scan_state_t *)state_;
    ts_stream_t *p_stream = state->p_stream;
    
    uint8_t *ts_packet = packet;
    
    // 取得pid
    uint16_t i_pid = ((uint16_t)(ts_packet[1] & 0x1f) << 8) + ts_packet[2];
    
    if (((scan_state_t *)state_)->scan_type & scan_type_eit) {
//        if (i_pid == TS_PID_EIT) {
            dvbpsi_packet_push(p_stream->epg.handle, ts_packet);
//        }
//        else if (i_pid == TS_PID_TOT) {
//            dvbpsi_packet_push(p_stream->tot.handle, ts_packet);
//        }
    }
    if (((scan_state_t *)state_)->scan_type & scan_type_program) {     // 解析PAT/SDT/PMT
        
        int        i_cc = (ts_packet[3] & 0x0f);              // continuity counter 连续计数器 一个4bit的计数器，范围0-15
        vlc_bool_t b_adaptation = (ts_packet[3] & 0x20);      // adaptation field 自适应控制 01仅含有效负载，10仅含调整字段，11含有调整字段和有效负载。为00解码器不进行处理
        vlc_bool_t b_discontinuity_seen = VLC_FALSE;         // i_cc 计算是否是连续报包
        
        if( i_pid == TS_PID_PAT )
        {
            if (state->scan_program_packet_type & scan_program_packet_pat) {
                if ( !p_stream->pat.b_seen ) dvbpsi_packet_push(p_stream->pat.handle, ts_packet);
            }
        }
        else if ( i_pid == TS_PID_SDT )
        {
            if (state->scan_program_packet_type & scan_program_packet_sdt) {
                if ( p_stream->pat.b_seen ) dvbpsi_packet_push(p_stream->sdt.handle, ts_packet);
            }
        }
        else if ( p_stream->pmts.first_pmt ) {   // 其余, 可能是PMT的音视频包
            if (state->scan_program_packet_type & scan_program_packet_pmt) {
                ts_pmt_t *tmp_pmt = p_stream->pmts.first_pmt;
                while ( tmp_pmt ) {
                    if ( i_pid == tmp_pmt->pid_pmt->i_pid ) {
                        dvbpsi_packet_push(tmp_pmt->handle, ts_packet);
                        break;
                    }
                    tmp_pmt = tmp_pmt->next;
                }
            }
        }
        
        
        /* Remember PID */
        if( !p_stream->pid[i_pid].b_seen )
        {
            p_stream->pid[i_pid].b_seen = VLC_TRUE;
            p_stream->pid[i_pid].i_cc = i_cc;
        }
        else
        {
            /* Check continuity counter */
            int i_diff = 0;
            
            i_diff = i_cc - (p_stream->pid[i_pid].i_cc + 1) % 16; // & 0x0f
            b_discontinuity_seen = ( i_diff != 0 );
            
            /* Update CC */
            p_stream->pid[i_pid].i_cc = i_cc;
        }
        
        
        /* Handle discontinuities if they occurred,
         * according to ISO/IEC 13818-1: DIS pages 20-22 */
        if( b_adaptation )
        {
            //                vlc_bool_t b_discontinuity_indicator = (ts_paket[5]&0x80);
            //                vlc_bool_t b_random_access_indicator = (ts_paket[5]&0x40);
            vlc_bool_t b_pcr = (ts_packet[5]&0x10);  /* PCR flag */
            
            //                if( b_discontinuity_indicator )
            //                    fprintf( stderr, "Discontinuity indicator (pid %d)\n", i_pid );
            //                if( b_random_access_indicator )
            //                    fprintf( stderr, "Random access indicator (pid %d)\n", i_pid );
            
            /* Dump PCR */
            if( b_pcr && (ts_packet[4] >= 7) )
            {
                mtime_t i_pcr;  /* 33 bits */
                
                i_pcr = ( ( (mtime_t)ts_packet[6] << 25 ) |
                         ( (mtime_t)ts_packet[7] << 17 ) |
                         ( (mtime_t)ts_packet[8] << 9 ) |
                         ( (mtime_t)ts_packet[9] << 1 ) |
                         ( (mtime_t)ts_packet[10] >> 7 ) ) / 90;
                //                    i_prev_pcr = p_stream->pid[i_pid].i_pcr;
                p_stream->pid[i_pid].i_pcr = i_pcr;
                
                if( b_discontinuity_seen )
                {
                    /* cc discontinuity is expected */
                    //                        fprintf( stderr, "Server signalled the continuity counter discontinuity\n" );
                    /* Discontinuity has been handled */
                    b_discontinuity_seen = VLC_FALSE;
                }
            }
        }
        
        if( b_discontinuity_seen )
        {
            //                fprintf( stderr, "Continuity counter discontinuity (pid %d found %d expected %d)\n",
            //                    i_pid, p_stream->pid[i_pid].i_cc, i_old_cc+1 );
            /* Discontinuity has been handled */
            b_discontinuity_seen = VLC_FALSE;
        }
    }
    

    return 0;
}

void post_call(void *state_)
{
    scan_state_t *state = (scan_state_t *)state_;
    ts_stream_t *p_stream = state->p_stream;
    
    if ( state->scan_type & scan_type_program ) {
        // free pat handle
        if ( state->p_stream->pat.b_seen && state->p_stream->pat.handle ) {
            dvbpsi_pat_detach( state->p_stream->pat.handle );
            dvbpsi_delete( state->p_stream->pat.handle );
            state->p_stream->pat.handle = NULL;
        }
        
        // free pmt handle
        if ( state->p_stream->pmts.b_seen && p_stream->pmts.first_pmt->handle) {
            ts_pmt_t *tmp_pmt = p_stream->pmts.first_pmt;
            while (tmp_pmt) {
                ts_pmt_t *temp = tmp_pmt->next;
                if( tmp_pmt->handle ) {
                    dvbpsi_pmt_detach(tmp_pmt->handle);
                    dvbpsi_delete( state->p_stream->pat.handle);
                    tmp_pmt->handle = NULL;
                }
                tmp_pmt = temp;
            }
        }
        
        
        // free sdt handle
        if ( state->p_stream->sdt.b_seen && state->p_stream->sdt.handle ) {
            if( p_stream->sdt.handle ) {
                dvbpsi_DetachDemux(p_stream->sdt.handle);
                dvbpsi_delete(p_stream->sdt.handle);
                state->p_stream->sdt.handle = NULL;
            }
        }

        
    }
    if ( state->scan_type & scan_type_eit ) {
        
        p_stream->epg.pf_tot_callback = NULL;
        p_stream->epg.pf_epg_segment_callback = NULL;
        p_stream->epg.pf_epg_table_callback = NULL;

        if( p_stream->tot.handle ) {
            dvbpsi_DetachDemux(p_stream->tot.handle);
            dvbpsi_delete(p_stream->tot.handle);
        }
        
        if( p_stream->epg.handle ) {
            dvbpsi_DetachDemux(p_stream->epg.handle);
            dvbpsi_delete(p_stream->epg.handle);
        }
    }

}

// Keep processing data until we've found PMT information.
//static int continuation_call(void *state_, void *p_data)
int continuation_call(void *state_, void *p_data, bool force)
{
    scan_state_t *state = (scan_state_t *)state_;
    
    if ( state->scan_type == scan_type_program ) {
        
        if ( state->scan_program_packet_done == state->scan_program_packet_type ) {
            if (state->p_stream->b_program_seen || force) {
                state->p_stream->b_program_seen = true;
                state->found = state->p_stream->b_program_seen?1:0;
                
                if (state->scan_complete_block) {
                    state->scan_complete_block(state_, p_data);
                    state->scan_complete_block = NULL;
                }
            }
            state->found = 1;
        }
    }
    else if ( state->scan_type == scan_type_eit ) {
        
    }

    // 中断之前先返回已扫描的信息
    if (_is_stop) state->found = -1; // 中断
    return state->found;
}

#pragma mark -
static uint8_t get_tableid(uint8_t *packet)
{
    // 取出首字节
    int i_begin_length = 4;
    switch( (packet[3] >> 4) & 0x03 ) // packet->header.adaption_field_control
    {
        case 0x0: break;
        case 0x1:
            i_begin_length += packet[i_begin_length] + 1;  // + pointer_field
            break;
        case 0x2: break;
        case 0x3:       // 既有 adaptation_field 也有 有效载荷
        {
            int adaptation_field_length = packet[4];
            if (adaptation_field_length > 0) {
                i_begin_length += adaptation_field_length;
            }
            i_begin_length += 1;
            i_begin_length += packet[i_begin_length] + 1;
        }
            break;
        default:
            break;
    }
    uint8_t *p_eit = packet + i_begin_length;
    uint8_t i_table_id = p_eit[0];
    
    
    uint8_t* p_payload_pos;               /* Where in the TS packet */
    uint8_t* p_new_pos = NULL;            /* Beginning of the new section */
    /* Return if no payload in the TS packet */
    if (!(packet[3] & 0x10)) return 0;
    
    /* Skip the adaptation_field if present */
    if (packet[3] & 0x20)
        p_payload_pos = packet + 5 + packet[4];       // ts_packet[4] 为 adaptation_field length
    else
        p_payload_pos = packet + 4;
    
    /* Unit start -> skip the pointer_field and a new section begins */
    if (packet[1] & 0x40)
    {
        p_new_pos = p_payload_pos + *p_payload_pos + 1;
        p_payload_pos += 1;
    }
    
    if (p_new_pos)
    {
        /* Update the position in the packet */
        p_payload_pos = p_new_pos;
        /* New section is being handled */
        p_new_pos = NULL;
    }
    uint8_t table_id = p_payload_pos[0];
    printf("%s-%s-%d\n", __FILE__, __FUNCTION__, p_payload_pos[0]);
    
    return table_id;
}


#pragma mark - Dump descriptors
/*****************************************************************************
 * dump_pmt_descriptors
 *****************************************************************************/
static void dump_pmt_descriptors(void* p_zero, dvbpsi_descriptor_t* p_descriptor)
{
    ts_pmt_t *pmt = (ts_pmt_t *)p_zero;
    while(p_descriptor) {
        if (p_descriptor->i_tag == 0xcf) { // unkown_descriptor
            p_descriptor = p_descriptor->p_next;
            continue;
        }
        
        int i;
        printf("%s 0x%02x : \"", "    |  ]", p_descriptor->i_tag);
        for(i = 0; i < p_descriptor->i_length; i++)
            printf("%c", p_descriptor->p_data[i]);
        printf("\"\n");
        
        //\x01\x03AVG\x15NationalGeographic HD
        //\x01             \x03                     AVG             \x15                    NationalGeographic HD
        // service_type    provider_name_length     provider_name   program_name_length     program_name
        
        
        int provider_name_length = p_descriptor->p_data[1];
        if ( 0 != provider_name_length ) {
            uint8_t *provider_name = (uint8_t *)malloc(provider_name_length);
            memcpy(provider_name, p_descriptor->p_data + 2, provider_name_length);
            pmt->i_provider_name_length = provider_name_length;
            pmt->c_provider_name = provider_name;
        }
        
        
        int program_name_length = p_descriptor->p_data[provider_name_length + 2];
        if ( 0 != program_name_length) {
            uint8_t *name = (uint8_t *)malloc(p_descriptor->i_length);
            memcpy(name, p_descriptor->p_data + provider_name_length + 2 + 1, program_name_length);
            pmt->i_name_length = program_name_length;
            pmt->c_program_name = name;
        }
        
        
        // 只取第一个, unkown_descriptor不取
        p_descriptor = p_descriptor->p_next;
    }
};



static void dump_supplemental_type_info(descriptor_type_t type, descriptor_info_t info, const char *indent)
{
    unsigned char i;
    char *temp;

    printf("\n");

    switch(type)
    {
        case max_bitrate:
        
            printf("%s('max_bitrate' descriptor info)\n\n", indent);
            printf("%si_max_bitrate: %u\n",                 indent, info.max_bitrate.i_max_bitrate);
        
            break;

        case system_clock:
        
            printf("%s('system_clock' descriptor info)\n\n", indent);
            printf("%s     b_external_clock_ref: %d\n",           indent, info.system_clock.b_external_clock_ref);
            printf("%s i_clock_accuracy_integer: %u\n",       indent, info.system_clock.i_clock_accuracy_integer);
            printf("%si_clock_accuracy_exponent: %u\n",      indent, info.system_clock.i_clock_accuracy_exponent);
            
            break;

        case stream_identifier:
        
            printf("%s('stream_identifier' descriptor info)\n\n", indent);
            printf("%si_component_tag: %u\n",                     indent, info.stream_identifier.i_component_tag);
            
            break;
        
        case subtitle:
        
            printf("%s('subtitle' descriptor info)\n\n", indent);
            printf("%scount: %u\n",                      indent, info.subtitle.count);
            
            if(info.subtitle.count)
            {
                printf("\n");

                i = 0;                
                while(i < info.subtitle.count)
                {
                    printf("%si_iso6392_language_code: %u, %u, %u\n", 
                            indent, 
                            info.subtitle.subtitles[i].i_iso6392_language_code[0], 
                            info.subtitle.subtitles[i].i_iso6392_language_code[1], 
                            info.subtitle.subtitles[i].i_iso6392_language_code[2]);
                    
                    printf("%s      i_subtitling_type: %u\n", 
                            indent, 
                            info.subtitle.subtitles[i].i_subtitling_type);

                    printf("%s  i_composition_page_id: %u\n", 
                            indent, 
                            info.subtitle.subtitles[i].i_composition_page_id);

                    printf("%s    i_ancillary_page_id: %u\n", 
                            indent, 
                            info.subtitle.subtitles[i].i_ancillary_page_id);

                    printf("\n");
                    
                    i++;
                }
            }
            
            break;

        case unknown:

            temp = strndup((char *)info.unknown.data, info.unknown.length);

            printf("%s('unknown' descriptor info)\n\n", indent);
            printf("%s  data: %s\n",                    indent, temp);
            printf("%slength: %u\n",                    indent, info.unknown.length);

            free(temp);

            break;
            
        default:
        
            printf("%s(invalid descriptor type (%u))\n\n", indent, type);
    }
}

static void dump_descriptors(descriptor_t *current, const char* indent)
{
    const char *indent_proper = (indent ? indent : "");

    unsigned char i = 0;
    while(current)
    {
        printf("%s%u\n",               indent_proper, i);
        printf("%s---\n",              indent_proper);
        printf("%s       i_tag: %u\n", indent_proper, current->i_tag); // Library's type.
        printf("%stype (local): %u\n", indent_proper, current->type);  // Our type.

        dump_supplemental_type_info(current->type, current->info, indent);
    
        printf("\n");
    
        current = current->next;
        i++;
    }
}

void dump_state_info(scan_state_t *state)
{
    const char *indent = "  ";

    if(state->p_stream->b_program_seen == 0)
    {
        printf("No PMT packets were found.\n\n");
        return;
    }
    
    ts_pmt_t *pmt = state->p_stream->pmts.first_pmt;
    while (pmt) {
        
        printf("General\n");
        printf("=======\n");
        
        printf("Program number: %u\n", pmt->i_number);
        printf("       Version: %u\n", pmt->i_pmt_version);
        printf("       PCR PID: %u\n", pmt->pid_pcr->i_pid);
        
        printf("\n");
        
        descriptor_t *current = pmt->pmt_descriptor;
        
        if(current)
            {
            printf("Descriptors (Regular)\n");
            printf("=====================\n");
            printf("\n");
            
            dump_descriptors(current, "");
            }
        
        descriptor_es_t *es_current = pmt->pmt_es_descriptor;
        
        if(es_current)
            {
            printf("Descriptors (ES)\n");
            printf("================\n");
            printf("\n");
            
            while(es_current)
                {
                printf("%s(New ES section)\n", indent);
                printf("\n");
                
                printf("%s   i_type: %u\n", indent, es_current->i_type);
                printf("%stype_name: %s\n", indent, es_current->type_name);
                printf("%s    i_pid: %u\n", indent, es_current->i_pid);
                
                printf("\n");
                
                if(es_current->next_child)
                    {
                    printf("%sDescriptors (Regular)\n", indent);
                    printf("%s=====================\n", indent);
                    
                    dump_descriptors(es_current->next_child, indent);
                    
                    printf("\n");
                    }
                
                es_current = es_current->next_sibling;
                }
            }
        
        pmt = pmt->next;
    }
    
    
}

#pragma mark - Convert

#pragma mark - Free
static void free_descriptor(descriptor_t *descriptor)
{
    if(!descriptor)
        return;
    
    free_descriptor(descriptor->next);
    
    // The only descriptor property that is malloc'd is stored on a subtitle
    // descriptor.
    if(descriptor->type == subtitle)
        free(descriptor->info.subtitle.subtitles);
    
    else if(descriptor->type == unknown)
        free(descriptor->info.unknown.data);
}

static void free_es_descriptor(descriptor_es_t *es_descriptor)
{
    if(!es_descriptor)
        return;
    
    free_es_descriptor(es_descriptor->next_sibling);
    free_descriptor(es_descriptor->next_child);
}

void free_event(ts_event_t *event) {
    if (event->event_name)
    free(event->event_name);
    if (event->event_decription)
    free(event->event_decription);
    if (event)
    free(event);
}

void free_subeit(ts_sub_eit_t *sub_eit) {
    ts_event_t *event = sub_eit->events.first_event;
    while (event) {
        ts_event_t *temp_event = event;
        event = event->next;
        free_event(temp_event);
    }
    if(sub_eit)
        free(sub_eit);
}

void free_state(scan_state_t *state)
{
    if(!state) return;
    
    ts_stream_t *p_stream = state->p_stream;
    
    if (state->scan_type & scan_type_program) {
        ts_pmt_t *tmp_pmt = p_stream->pmts.first_pmt;
        while (tmp_pmt) {
            free(tmp_pmt->c_program_name);
            free(tmp_pmt->c_provider_name);
            
            ts_pmt_t *temp = tmp_pmt;
            tmp_pmt = tmp_pmt->next;
            free(temp);
        }
    }
    
    if (state->scan_type & scan_type_eit) {
        
        ts_eits_t *eits = p_stream->epg.first_eits;
        while (eits) {
            
            ts_sub_eit_t *sub_eit = eits->first_eit;
            while (sub_eit) {
                ts_sub_eit_t *temp_sub_eit = sub_eit;
                sub_eit = sub_eit->next;
                free_subeit(temp_sub_eit);
            }
            
            ts_eits_t *temp_eits = eits;
            eits = eits->next;
            free(temp_eits);
        }
    }
    
    if (state->p_stream)
        free(state->p_stream);
    
    free(state);
}

#pragma mark -
int scan_program_block( int dtvmode, int frequency, scan_complete_t pf_complete_cb, void *p_data )
{
    assert(pf_complete_cb);
    
    _is_stop = false;
    
    int result;
    scan_state_t *state = (scan_state_t *)malloc(sizeof(scan_state_t));
    memset(state, 0, sizeof(scan_state_t));
    
    ts_stream_t *p_stream = (ts_stream_t *)malloc(sizeof(ts_stream_t));
    memset(p_stream, 0, sizeof(ts_stream_t));
    
    if( !state && !p_stream ) return -1;
    
    state->p_stream = p_stream;
    
    state->dtvmode = dtvmode;
    state->frequency = frequency;
    state->private_data = p_data;
    state->scan_complete_block = pf_complete_cb;
    
    state->scan_type = scan_type_program;
    state->scan_program_packet_type = scan_program_packet_pat | scan_program_packet_pmt | scan_program_packet_sdt;
    
    
    result = scan_stream(pre_call,
                         process_call,
                         post_call,
                         continuation_call,
                         state,
                         100,
                         p_data);
    
    if(state) free_state(state);
    
    return result;
}

#pragma mark - Public
int scan_program( int dtvmode, int frequency, bool block, scan_complete_t pf_complete_cb, void *p_data )
{
    printf("%s-%s-开始节目\n", __FILE__, __FUNCTION__);
    struct timeval t_val;
    gettimeofday(&t_val, NULL);
    
    int ret = 0;
    if (block) {
        ret = scan_program_block(dtvmode, frequency, pf_complete_cb, p_data);
    }
    else {
        ret = scan_program_noblock( dtvmode, frequency, pf_process_cb, pf_complete_cb, p_data);
    }
    
    // 计算耗时
    struct timeval t_val_end;
    gettimeofday(&t_val_end, NULL);
    struct timeval t_result;
    timersub(&t_val_end, &t_val, &t_result);
    double consume = t_result.tv_sec + (1.0 * t_result.tv_usec)/1000000;
    printf("%s-%s-完成扫描花费时间: %fs\n", __FILE__, __FUNCTION__, consume);
    
    return ret;
}

extern int scan_epg_table( scan_epg_table_callback epg_table_callback, scan_epg_tot_callback epg_tot_callback, void *p_data ) {

    printf("%s-%s-开始扫描EIT\n", __FILE__, __FUNCTION__);
    _is_stop = false;
    
    int result;
    scan_state_t *state = (scan_state_t *)malloc(sizeof(scan_state_t));
    memset(state, 0, sizeof(scan_state_t));
    
    ts_stream_t *p_stream = (ts_stream_t *)malloc(sizeof(ts_stream_t));
    memset(p_stream, 0, sizeof(ts_stream_t));
    
    if( !state && !p_stream ) return -1;
    
    state->p_stream = p_stream;
    state->p_stream->epg.pf_epg_table_callback = epg_table_callback;
    state->p_stream->epg.pf_tot_callback = epg_tot_callback;
    state->private_data = p_data;
    
    state->scan_type = scan_type_eit;
    
    result = scan_stream(pre_call,
                         process_call,
                         post_call,
                         continuation_call,
                         state,
                         200,
                         p_data);
    
    if (state) free_state(state);

    return result;
}

int scan_epg_segment(scan_epg_segment_callback epg_segment_callback, scan_epg_tot_callback epg_tot_callback, void *p_data)
{
    printf("%s-%s-开始扫描EIT\n", __FILE__, __FUNCTION__);
    _is_stop = false;
    
    int result;
    scan_state_t *state = (scan_state_t *)malloc(sizeof(scan_state_t));
    memset(state, 0, sizeof(scan_state_t));
    
    ts_stream_t *p_stream = (ts_stream_t *)malloc(sizeof(ts_stream_t));
    memset(p_stream, 0, sizeof(ts_stream_t));
    
    if( !state && !p_stream ) return -1;
    
    state->p_stream = p_stream;
    state->private_data = p_data;
    
    int temp[] = {0x4E, 0x50, 0x51};        // 默认值
    state->p_stream->epg.arr_need_parse_tid = temp;
    state->p_stream->epg.i_need_parse_tid_sum = 3;
    
    state->p_stream->epg.pf_epg_segment_callback = epg_segment_callback;
    state->p_stream->epg.pf_tot_callback = epg_tot_callback;

    state->scan_type = scan_type_eit;
    
    result = scan_stream(pre_call,
                         process_call,
                         post_call,
                         continuation_call,
                         state,
                         200,
                         p_data);
    
    if (state) free_state(state);
    
    return result;
}

int scan_program_with_epg(int dtvmode, int frequency, scan_complete_t block, scan_epg_complete_callback epg_block, int *eit_tid, int eit_tid_sum, void *p_data)
{
    assert(block);
    
#if defined(__APPLE__)
    // 计算代码耗时s ------------------------------------------------------> 开始
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
#endif
    
    printf("%s-%s-开始扫描EIT\n", __FILE__, __FUNCTION__);
    _is_stop = false;
    
    scan_state_t *state = (scan_state_t *)malloc(sizeof(scan_state_t));
    memset(state, 0, sizeof(scan_state_t));
    
    ts_stream_t *p_stream = (ts_stream_t *)malloc(sizeof(ts_stream_t));
    memset(p_stream, 0, sizeof(ts_stream_t));
    
    if( !state && !p_stream ) return -1;
    
    state->p_stream = p_stream;
    
    state->dtvmode = dtvmode;
    state->frequency = frequency;
    state->private_data = p_data;
    state->scan_complete_block = block;
    state->pf_epg_complete_callback = epg_block;
    
    int temp[] = {0x4E, 0x50, 0x51};        // 默认值
    state->p_stream->epg.arr_need_parse_tid = eit_tid != NULL ? eit_tid : temp;
    state->p_stream->epg.i_need_parse_tid_sum = eit_tid != NULL ? eit_tid_sum : 3;
    
    state->scan_type = scan_type_eit | scan_type_program;
    
    // 扫描节目
    //    state->scan_type = scan_type_program;
    int result = scan_stream(pre_call,
                             process_call,
                             post_call,
                             continuation_call,
                             state,
                             200,
                             p_data);
    //    if (result == 0) block(state, p_data);
    //    else block(NULL, p_data);
    
    
    // 扫描EPG
    //    state->scan_type = scan_type_eit;
    //    result = scan_stream(pre_call,
    //                         process_call,
    //                         NULL,
    //                         continuation_call,
    //                         state);
    //
    //    if (result == 0) block(state, p_data);
    //    else block(NULL, p_data);
    
    if(state) free_state(state);
    
#if defined(__APPLE__)
    printf("%s-%s->>>>>>>>>>cost time = %f ms\n", __FILE__, __FUNCTION__, CFAbsoluteTimeGetCurrent() - startTime);
    // 计算代码耗时s ------------------------------------------------------> 结束
#endif
    return result;
}

int scan_program_with_epg2(int dtvmode, int frequency, scan_complete_t block, int *eit_tid, int eit_tid_sum, void *p_data) {
    assert(block);
    
    #if defined(__APPLE__)
    // 计算代码耗时s ------------------------------------------------------> 开始
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    #endif
    
    printf("%s-%s-开始扫描EIT\n", __FILE__, __FUNCTION__);
    _is_stop = false;
    
    scan_state_t *state = (scan_state_t *)malloc(sizeof(scan_state_t));
    memset(state, 0, sizeof(scan_state_t));
    
    ts_stream_t *p_stream = (ts_stream_t *)malloc(sizeof(ts_stream_t));
    memset(p_stream, 0, sizeof(ts_stream_t));
    
    if( !state && !p_stream ) return -1;
    
    state->p_stream = p_stream;
    
    state->dtvmode = dtvmode;
    state->frequency = frequency;
    state->private_data = p_data;
    state->scan_complete_block = block;
    state->pf_epg_complete_callback = block;

    int temp[] = {0x4E, 0x50, 0x51};        // 默认值
    state->p_stream->epg.arr_need_parse_tid = eit_tid != NULL ? eit_tid : temp;
    state->p_stream->epg.i_need_parse_tid_sum = eit_tid != NULL ? eit_tid_sum : 3;
    
    state->scan_type = scan_type_eit | scan_type_program;
    
    // 扫描节目
    //    state->scan_type = scan_type_program;
    int result = scan_stream(pre_call,
                             process_call,
                             post_call,
                             continuation_call,
                             state,
                             200,
                             p_data);
    //    if (result == 0) block(state, p_data);
    //    else block(NULL, p_data);
    
    
    // 扫描EPG
    //    state->scan_type = scan_type_eit;
    //    result = scan_stream(pre_call,
    //                         process_call,
    //                         NULL,
    //                         continuation_call,
    //                         state);
    //
    //    if (result == 0) block(state, p_data);
    //    else block(NULL, p_data);
    
    if(state) free_state(state);
    
    #if defined(__APPLE__)
    printf("%s-%s->>>>>>>>>>cost time = %f ms\n", __FILE__, __FUNCTION__, CFAbsoluteTimeGetCurrent() - startTime);
    // 计算代码耗时s ------------------------------------------------------> 结束
    #endif
    return result;
}


int stop_scan(void) {
    _is_stop = true;
    
    return 0;
}


