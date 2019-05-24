//
//  ts_scan_program_extend.c
//  DTV
//
//  Created by ShiftTime on 2019/1/31.
//  Copyright © 2019 SFT. All rights reserved.
//

#include <stdio.h>
#include <stdbool.h>
#include <assert.h>
#include <stdlib.h>
#include <string.h>

#include "ts_scan_program_extend.h"
#include "ts_scan_program.h"
#include "ts_scanner.h"

#include "ns_tvclient_interface.h"

int scan_program_packet(scan_state_t **p_state, scan_program_packet_type_t packet_type, int packet_count, int dtvmode, int frequency, scan_complete_t block, void *p_data)
{
    scan_state_t *state;
    if (*p_state == NULL) {
        state = (scan_state_t *)malloc(sizeof(scan_state_t));
        memset(state, 0, sizeof(scan_state_t));
        *p_state = state;
        
        ts_stream_t *p_stream = (ts_stream_t *)malloc(sizeof(ts_stream_t));
        memset(p_stream, 0, sizeof(ts_stream_t));
        
        if( !state && !p_stream ) return -1;
        state->p_stream = p_stream;
        
        state->dtvmode = dtvmode;
        state->frequency = frequency;
        state->private_data = p_data;
    }
    else state = *p_state;
    
    state->found = 0;
    state->scan_complete_block = block;
    state->scan_type = scan_type_program;
    state->scan_program_packet_type = packet_type; //scan_program_packet_pat | scan_program_packet_sdt;
    state->scan_program_packet_done = 0;
    
    int result = scan_stream(pre_call,
                             process_call,
                             post_call,
                             continuation_call,
                             state,
                             packet_count,
                             p_data);
    
    //    if(state) free_state(state);
    
    return result;
}

void receive_data_callback(void *tsbuf, unsigned int bufsize) {
    stream_entry(tsbuf, bufsize);
}

int pf_process_cb(void *p_data, int *pids, int pid_count, int dtvmode, int freq, bool b_block, int bufsize, bool b_set_channel) {
    
    if (sft_tvtune_regist_data_callback(receive_data_callback, bufsize)) {
        printf("%s-%s-sft_tvtune_regist_data_callback fail\n", __FILE__, __FUNCTION__);
        return -1;
    }
    
    if ( b_set_channel && sft_tvtune_set_channel(freq, dtvmode) ) {
        printf("%s-%s-error: sft_tvtune_set_channel\n", __FILE__, __FUNCTION__);
        sft_tvtune_cancel_pidservice();
        return -1;
    }
    
    dtv_pid_t pidlist[pid_count];
    for (int i = 0; i < pid_count; i++) {
        pidlist[i].pid = pids[i];
    }
    
    if ( sft_tvtune_select_pidservice(b_block, pidlist, pid_count) ) {
        printf("%s-%s-sft_tvtune_select_pidservice fail\n", __FILE__, __FUNCTION__);
        return -1;
    }
    
    return 0;
}

#define min(x,y) ({ \
typeof(x) _x = (x); \
typeof(y) _y = (y); \
(void) (&_x == &_y); \
_x < _y ? _x : _y; })
/* FIXME: scan_program_block */
int scan_program_noblock( int dtvmode, int freq, scan_program_process_t pf_process_cb, scan_complete_t pf_complete_cb, void *p_data ) {
    
    _is_stop = false;

    assert(pf_process_cb);
    if (pf_process_cb == NULL) return -1;
    
    // block
    int pids[] = { 0x0000, 0x0011 };
    scan_state_t *p_state = NULL;
    int scan_type = scan_program_packet_pat | scan_program_packet_sdt;
    int packet_count = 3;
    if ( pf_process_cb( p_data, pids, 2, dtvmode, freq, false, packet_count * 188, true ) ) {
        printf("%s-%s-pull stream fail\n", __FILE__, __FUNCTION__);
        return -1;
    }
    
    int ret = scan_program_packet(&p_state, scan_type, packet_count, dtvmode, freq, NULL, p_data);
    if (ret != 0) {
        return -1;
    }
    
    
    if (p_state && p_state->p_stream->pat.b_seen) {
        /* FIXME: 使用pmts->i_pids */
        int pmt_pids[100] = {0};
        int count = 0;
        ts_pmt_t *pmt = p_state->p_stream->pmts.first_pmt;
        while (pmt) {
            pmt_pids[count] = pmt->pid_pmt->i_pid;
            count += 1;
            pmt = pmt->next;
        }
        int scan_type = scan_program_packet_pmt;
        if (p_state->p_stream->sdt.b_seen == false) {
            scan_type |= scan_program_packet_sdt;
            pmt_pids[count] = 0x0011;
            count += 1;
        }
        
        int packet_count = (int)min(count * 5, 100);
        if ( pf_process_cb( p_data, pmt_pids, count, dtvmode, freq, false, packet_count * 188, false )) {
            printf("%s-%s-pull stream fail\n", __FILE__, __FUNCTION__);
            return -1;
        }
        
        int ret = scan_program_packet(&p_state, scan_type, packet_count, dtvmode, freq, pf_complete_cb, p_data);
        if (ret != 0) {
            return -1;
        }
    }
    
    free_state(p_state);
    
    return 0;
}

