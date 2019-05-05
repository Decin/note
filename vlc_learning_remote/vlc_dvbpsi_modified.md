## 使用libdvbpsi eit dump segment 版本, vlc源码中的修改
### 1.libdvbpsi中的修改
#### libdvbpsi-1.3.2/src/dvbpsi.h
```
struct dvbpsi_s
{
    dvbpsi_decoder_t             *p_decoder;          /*!< private pointer to
                                                       specific decoder */
    /* Messages callback */
    dvbpsi_message_cb             pf_message;           /*!< Log message callback */
    enum dvbpsi_msg_level         i_msg_level;          /*!< Log level */
    
    /* private data pointer for use by caller, not by libdvbpsi itself ! */
    void                         *p_sys;                /*!< pointer to private data
                                                         from caller. Do not use
                                                         from inside libdvbpsi. It
                                                         will crash any application. */
    
    // modified 增加b_segment_dump
    bool                        b_segment_dump;
    
};
```

####libdvbpsi-1.3.2/src/tables/eit.h
```
// modified dvbpsi_eit_callback 增加参数 bool b_complete
typedef void (* dvbpsi_eit_callback)(void* p_cb_data, dvbpsi_eit_t* p_new_eit, bool b_complete);
```


####libdvbpsi-1.3.2/src/tables/eit.c
```
void dvbpsi_eit_sections_gather(dvbpsi_t *p_dvbpsi, dvbpsi_decoder_t *p_private_decoder,
                                dvbpsi_psi_section_t *p_section)
{
    assert(p_dvbpsi);
    assert(p_dvbpsi->p_decoder);
    
    const uint8_t i_table_id = (p_section->i_table_id >= 0x4e &&
                                p_section->i_table_id <= 0x6f) ?
    p_section->i_table_id : 0x4e;
    
    if (!dvbpsi_CheckPSISection(p_dvbpsi, p_section, i_table_id, "EIT decoder"))
        {
        dvbpsi_DeletePSISections(p_section);
        return;
        }
    
    /* We have a valid EIT section */
    dvbpsi_demux_t *p_demux = (dvbpsi_demux_t *) p_dvbpsi->p_decoder;
    dvbpsi_eit_decoder_t* p_eit_decoder
    = (dvbpsi_eit_decoder_t*)p_private_decoder;
    
    /* TS discontinuity check */
    if (p_demux->b_discontinuity)
        {
        dvbpsi_ReInitEIT(p_eit_decoder, true);
        p_eit_decoder->b_discontinuity = false;
        p_demux->b_discontinuity = false;
        }
    else
        {
        /* Perform a few sanity checks */
        if (p_eit_decoder->p_building_eit)
            {
            if (dvbpsi_CheckEIT(p_dvbpsi, p_eit_decoder, p_section))
                dvbpsi_ReInitEIT(p_eit_decoder, true);
            }
        else
            {
            if (   (p_eit_decoder->b_current_valid)
                && (p_eit_decoder->current_eit.i_version == p_section->i_version)
                && (p_eit_decoder->current_eit.b_current_next == p_section->b_current_next))
                {
                /* Don't decode since this version is already decoded */
                dvbpsi_debug(p_dvbpsi, "EIT decoder",
                             "ignoring already decoded section %d",
                             p_section->i_number);
                dvbpsi_DeletePSISections(p_section);
                return;
                }
            }
        }
    
    bool b_complete = dvbpsi_IsCompleteEIT(p_eit_decoder, p_section);
    
    /* Add section to EIT */
    if (!dvbpsi_AddSectionEIT(p_dvbpsi, p_eit_decoder, p_section))
        {
        dvbpsi_error(p_dvbpsi, "EIT decoder", "failed decoding section %d",
                     p_section->i_number);
        dvbpsi_DeletePSISections(p_section);
        return;
        }
    
    /* Check if we have all the sections */
    if (b_complete)
        {
        assert(p_eit_decoder->pf_eit_callback);
        
        /* Save the current information */
        p_eit_decoder->current_eit = *p_eit_decoder->p_building_eit;
        p_eit_decoder->b_current_valid = true;
        
        /* Decode the sections */
        dvbpsi_eit_sections_decode(p_eit_decoder->p_building_eit,
                                   p_eit_decoder->p_sections);
        
        /* signal the new EIT */
//        p_eit_decoder->pf_eit_callback(p_eit_decoder->p_cb_data, p_eit_decoder->p_building_eit);
        // modified 增加一个参数
        p_eit_decoder->pf_eit_callback(p_eit_decoder->p_cb_data, p_eit_decoder->p_building_eit, true);
        
        /* Delete sections and Reinitialize the structures */
        dvbpsi_ReInitEIT(p_eit_decoder, false);
        assert(p_eit_decoder->p_sections == NULL);
        }
    
    // modified 增加else部分
    else {
        
        if (p_dvbpsi->b_segment_dump) {
            dvbpsi_debug( p_dvbpsi, "EIT decoder", "--------------test epg segment p_dvbpsi->b_segment_dump : 1");
            /* Decode the sections */
            dvbpsi_eit_t temp_eit = *p_eit_decoder->p_building_eit;
            dvbpsi_eit_sections_decode(&temp_eit,
                                       p_eit_decoder->p_sections);
            /* signal the new EIT */
            p_eit_decoder->pf_eit_callback(p_eit_decoder->p_cb_data, &temp_eit, false);
            dvbpsi_eit_empty(&temp_eit);
        }
        else {
            dvbpsi_debug( p_dvbpsi, "EIT decoder", "--------------test epg segment p_dvbpsi->b_segment_dump : 0");
        }
    }
}
```

### 2.以下是vlc源码中的修改
#### .../vlc/modules/demux/mpeg/ts_streams.c
```
static inline bool handle_Init( demux_t *p_demux, dvbpsi_t **handle )
{
    *handle = dvbpsi_new( &dvbpsi_messages, DVBPSI_MSG_DEBUG );
    (*handle)->b_segment_dump = true;   // modified
    if( !*handle )
        return false;
    (*handle)->p_sys = (void *) p_demux;
    return true;
}
```


#### .../vlc/modules/demux/mpeg/ts_si.c
```
// modified 方法增加一个参数 bool b_complete, 内部 dvbpsi_eit_delete( p_eit ) 前增加判断if (b_complete)
static void EITCallBack( demux_t *p_demux, dvbpsi_eit_t *p_eit, bool b_complete )
{
    msg_Dbg( p_demux, "--------------test epg new i_table_id=%"PRIu16, p_eit->i_table_id);
    //    if (!b_complete) return;  // 在使用外部tsscaner解析epg时, 打开此处
    
    demux_sys_t        *p_sys = p_demux->p_sys;
    const dvbpsi_eit_event_t *p_evt;
    uint64_t i_runevt = 0;
    uint64_t i_fallbackevt = 0;
    vlc_epg_t *p_epg;
    
    msg_Dbg( p_demux, "EITCallBack called" );
    if( !p_eit->b_current_next )
        {
        if (b_complete) // modified
            dvbpsi_eit_delete( p_eit );
        return;
        }
    
    msg_Dbg( p_demux, "new EIT service_id=%"PRIu16" version=%"PRIu8" current_next=%d "
            "ts_id=%"PRIu16" network_id=%"PRIu16" segment_last_section_number=%"PRIu8" "
            "last_table_id=%"PRIu8,
            p_eit->i_extension,
            p_eit->i_version, p_eit->b_current_next,
            p_eit->i_ts_id, p_eit->i_network_id,
            p_eit->i_segment_last_section_number, p_eit->i_last_table_id );
    
    /* Use table ID for segmenting our EPG tables updates. 1 table id has 256 sections which
     * represents 8 segements of 32 sections each. Thus a max of 24 hours per table ID
     * (Should be even better with tableid+segmentid compound if dvbpsi would export segment id)
     * see TS 101 211, 4.1.4.2.1 */
    p_epg = vlc_epg_New( p_eit->i_table_id, p_eit->i_extension );
    if( !p_epg )
        {
        if (b_complete) // modified
            dvbpsi_eit_delete( p_eit );
        return;
        }
    
    for( p_evt = p_eit->p_first_event; p_evt; p_evt = p_evt->p_next )
        {
        dvbpsi_descriptor_t *p_dr;
        int64_t i_start;
        int i_duration;
        
        i_start = EITConvertStartTime( p_evt->i_start_time );
        SI_DEBUG_TIMESHIFT(i_start);
        i_duration = EITConvertDuration( p_evt->i_duration );
        
        /* We have to fix ARIB-B10 as all timestamps are JST */
        if( p_sys->standard == TS_STANDARD_ARIB )
            {
            /* See comments on TDT callback */
            i_start += 9 * 3600;
            }
        
        msg_Dbg( p_demux, "  * event id=%"PRIu16" start_time:%"PRId64" duration=%d "
                "running=%"PRIu8" free_ca=%d",
                p_evt->i_event_id, i_start, i_duration,
                p_evt->i_running_status, p_evt->b_free_ca );
        
        /* */
        if( i_start <= 0 )
            continue;
        
        vlc_epg_event_t *p_epgevt = vlc_epg_event_New( p_evt->i_event_id,
                                                      i_start, i_duration );
        if( !p_epgevt )
            continue;
        
        if( !vlc_epg_AddEvent( p_epg, p_epgevt ) )
            {
            vlc_epg_event_Delete( p_epgevt );
            continue;
            }
        
        for( p_dr = p_evt->p_first_descriptor; p_dr; p_dr = p_dr->p_next )
            {
            switch(p_dr->i_tag)
                {
                    case 0x4d:
                    {
                    dvbpsi_short_event_dr_t *pE = dvbpsi_DecodeShortEventDr( p_dr );
                    
                    /* Only take first description, as we don't handle language-info
                     for epg atm*/
                    if( pE )
                        {
                        char **ppsz = &p_epgevt->psz_name;
                        free( *ppsz );
                        *ppsz = EITConvertToUTF8( p_demux,
                                                 pE->i_event_name, pE->i_event_name_length,
                                                 p_sys->b_broken_charset );
                        ppsz = &p_epgevt->psz_short_description;
                        free( *ppsz );
                        *ppsz = EITConvertToUTF8( p_demux,
                                                 pE->i_text, pE->i_text_length,
                                                 p_sys->b_broken_charset );
                        msg_Dbg( p_demux, "    - short event lang=%3.3s '%s' : '%s'",
                                pE->i_iso_639_code, p_epgevt->psz_name, *ppsz );
                        }
                    }
                    break;
                    
                    case 0x4e:
                    {
                    dvbpsi_extended_event_dr_t *pE = dvbpsi_DecodeExtendedEventDr( p_dr );
                    if( pE )
                        {
                        msg_Dbg( p_demux, "    - extended event lang=%3.3s [%"PRIu8"/%"PRIu8"]",
                                pE->i_iso_639_code,
                                pE->i_descriptor_number, pE->i_last_descriptor_number );
                        
                        if( pE->i_text_length > 0 )
                            {
                            char *psz_text = EITConvertToUTF8( p_demux,
                                                              pE->i_text, pE->i_text_length,
                                                              p_sys->b_broken_charset );
                            if( psz_text )
                                {
                                msg_Dbg( p_demux, "       - text='%s'", psz_text );
                                
                                if( p_epgevt->psz_description )
                                    {
                                    size_t i_total = strlen( p_epgevt->psz_description ) + strlen( psz_text ) + 1;
                                    char *psz_realloc = realloc( p_epgevt->psz_description, i_total );
                                    if( psz_realloc )
                                        {
                                        p_epgevt->psz_description = psz_realloc;
                                        strcat( psz_realloc, psz_text );
                                        }
                                    free( psz_text );
                                    }
                                else
                                    {
                                    p_epgevt->psz_description = psz_text;
                                    }
                                }
                            }
                        
                        EITExtractDrDescItems( p_demux, pE, p_epgevt );
                        }
                    }
                    break;
                    
                    case 0x55:
                    {
                    dvbpsi_parental_rating_dr_t *pR = dvbpsi_DecodeParentalRatingDr( p_dr );
                    if ( pR )
                        {
                        int i_min_age = 0;
                        for ( int i = 0; i < pR->i_ratings_number; i++ )
                            {
                            const dvbpsi_parental_rating_t *p_rating = & pR->p_parental_rating[ i ];
                            if ( p_rating->i_rating > 0x00 && p_rating->i_rating <= 0x0F )
                                {
                                if ( p_rating->i_rating + 3 > i_min_age )
                                    i_min_age = p_rating->i_rating + 3;
                                msg_Dbg( p_demux, "    - parental control set to %d years",
                                        i_min_age );
                                }
                            }
                        p_epgevt->i_rating = i_min_age;
                        }
                    }
                    break;
                    
                    default:
                    msg_Dbg( p_demux, "    - event unknown dr 0x%"PRIx8"(%"PRIu8")", p_dr->i_tag, p_dr->i_tag );
                    break;
                }
            }
        
        switch ( p_evt->i_running_status )
            {
                case TS_SI_RUNSTATUS_RUNNING:
                if( i_runevt == 0 )
                    i_runevt = i_start;
                break;
                case TS_SI_RUNSTATUS_UNDEFINED:
                {
                if( i_fallbackevt == 0 &&
                   i_start <= p_sys->i_network_time &&
                   p_sys->i_network_time < i_start + i_duration )
                    i_fallbackevt = i_start;
                break;
                }
                default:
                break;
            }
        }
    
    /* Update "now playing" field */
    if( i_runevt || i_fallbackevt )
        vlc_epg_SetCurrent( p_epg, (i_runevt) ? i_runevt : i_fallbackevt );
    
    if( p_epg->i_event > 0 )
        {
        if( p_epg->b_present && p_epg->p_current )
            {
            ts_pat_t *p_pat = ts_pid_Get(&p_sys->pids, 0)->u.p_pat;
            ts_pmt_t *p_pmt = ts_pat_Get_pmt(p_pat, p_eit->i_extension);
            if(p_pmt)
                {
                p_pmt->eit.i_event_start = p_epg->p_current->i_start;
                p_pmt->eit.i_event_length = p_epg->p_current->i_duration;
                }
            }
        p_epg->b_present = (p_eit->i_table_id == 0x4e);
        es_out_Control( p_demux->out, ES_OUT_SET_GROUP_EPG, p_eit->i_extension, p_epg );
        }
    vlc_epg_Delete( p_epg );
    
    if (b_complete) // modified
        dvbpsi_eit_delete( p_eit );
}
```
