/*****************************************************************************
 * decode_mpeg.c: MPEG decoder example
 *----------------------------------------------------------------------------
 * Copyright (C) 2001-2010 VideoLAN
 * $Id: decode_mpeg.c 104 2005-03-21 13:38:56Z massiot $
 *
 * Authors: Jean-Paul Saman <jpsaman #_at_# m2x dot nl>
 *          Arnaud de Bossoreille de Ribou <bozo@via.ecp.fr>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 *
 *----------------------------------------------------------------------------
 *
 *****************************************************************************/

//#include "config.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <math.h>
#include <inttypes.h>
#include <stdbool.h>

#include "ns_variable_queue.h"
#include "ts_scanner.h"


#pragma mark - Free
void free_list(ts_pmt_t *Head)
{
    ts_pmt_t *Pointer;
    
    while (NULL != Head) {
        Pointer = Head;
        Head = Head->next;  // 下一个节点
        free(Pointer);
    }
    
    return;
}

void free_resource(void) {
    
}

#pragma mark -
static ts_queue_t bufQueue;

int scan_stream(pre_callback_t pre_callback,
                process_callback_t process_callback,
                post_callback_t post_callback,
                continuation_check_callback_t continuation_callback,
                void *state,
                int packet_count,
                void *p_data)
{
    // init queue
    if (!bufQueue.abhead) {
        init_variable_queue(&bufQueue, 1024 * 50 * 188);
    }
    
    int read_paket_count = packet_count ?: 200;     // 每次读取包的数量
    int read_bytes = read_paket_count * 188;     // 每次读取字节数
    
    /** 存储每次读取的一个ts包 */
    uint8_t *read_buffer = (uint8_t *)malloc(sizeof(uint8_t) * read_bytes);
    if( !read_buffer ) return -2;
    
    // 预处理, 创建handle
    if( pre_callback(state) != 0 ) return -4;
    
    
    // 设置超时时间
    float timeout = kScanTimeOut;
    time_t start_time = time(NULL);

    int ret = 0;
    while(1) {
        
        // 是否持续处理检测
        int con_ret = continuation_callback(state, p_data, false);
        if (con_ret != 0) {
            if (con_ret == -1) ret = -1;    // 出错
            break;
        }
        
        /* FIXME: 由于网络原因(如: recv ts error or timeout[-1, 35, Resource temporarily unavailable), 队列没有数据的问题, 导致陷入while循环; 设置超时解决 */
        time_t end_time = time(NULL);
        long duration = end_time - start_time;
        
        if (duration >= timeout) {
            continuation_callback(state, p_data, true);
            ret = -2;
            printf("%s-%s-超时退出\n", __FILE__, __FUNCTION__);
            break;
        }
        
        if (!bufQueue.abhead) break;
        if (is_empty_variable_queue(&bufQueue)) {
            usleep(10000);
            continue;
        }
        
        // read data
        memset(read_buffer, 0, sizeof(uint8_t) * read_bytes);

        //新接口
        int i_read_len = out_variable_queue2(&bufQueue, read_buffer, read_bytes);
        if (i_read_len == 0 || i_read_len % 188 != 0) continue;

        printf("%s-%s-出队 %d\n", __FILE__, __FUNCTION__, read_bytes);
        
        // handle out data
        int count = i_read_len / 188;
        uint8_t *temp = read_buffer;
        int read_fd = 0;
        while (read_fd < count) {
            
//            printf("%s-%s-读取位置 %d\n", __FILE__, __FUNCTION__, read_fd);
            temp = read_buffer + read_fd * 188;
            
            // 处理ts paket
            process_callback(temp, state);

            read_fd++;
        }
    }

    
    // 释放handle等
    if (post_callback) post_callback(state);
    
    
    // empty and free queue
    empty_variable_queue(&bufQueue);
    clear_variable_queue(&bufQueue);

    if(read_buffer) free(read_buffer);

    return ret;
}

int stream_entry(void *tsbuf, unsigned int bufsize) {
    printf("%s-%s-入队 %d\n", __FILE__, __FUNCTION__, bufsize);
    
//    if (0 != continuation_call()) {
//        return -1;
//    }
    
    // 扫描结束时, buffer queue 已经释放, 不会进入queue, 直接退出
    if (!bufQueue.abhead) return -1;
    
    int entersize = enter_variable_queue(&bufQueue, tsbuf, bufsize, 0);
    
    printf("%s-%s-队列大小 %d\n", __FILE__, __FUNCTION__, bufQueue.qsize);
    return entersize;
}


