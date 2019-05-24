//
//  ts_scan_program_extend.h
//  DTV
//
//  Created by ShiftTime on 2019/1/31.
//  Copyright © 2019 SFT. All rights reserved.
//

#ifndef ts_scan_program_extend_h
#define ts_scan_program_extend_h


#include "ts_scan_public.h"
typedef int (*scan_program_process_t)(void *p_data, int *pids, int pid_count, int dtvmode, int freq, bool b_block, int bufsize, bool b_set_channel);
extern int pf_process_cb( void *p_data, int *pids, int pid_count, int dtvmode, int freq, bool b_block, int bufsize, bool b_set_channel );
extern int scan_program_noblock( int dtvmode, int freq, scan_program_process_t pf_process_cb, scan_complete_t pf_complete_cb, void *p_data );

#endif /* ts_scan_program_extend_h */
