#ifndef ts_scan_program_h
#define ts_scan_program_h

#include "ts_scan_public.h"

extern void free_state(scan_state_t *state);
extern void dump_state_info(scan_state_t *state);

extern int pre_call(void *state_);
extern int process_call(void *packet, void *state_);
extern void post_call(void *state_);
extern int continuation_call(void *state_, void *p_data, bool force);

extern bool _is_stop;

#endif /* ts_scan_program_h */

