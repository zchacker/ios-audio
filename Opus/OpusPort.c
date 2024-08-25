//
//  OpusPort.c
//  Audio Chat
//
//  Created by Brown Diamond Tech on 7/27/24.
//

#include "OpusPort.h"
#include "include/opus/opus_defines.h"
#include "include/opus/opus_multistream.h"
#include "include/opus/opus_projection.h"
#include "include/opus/opus_types.h"
#include "include/opus/opus.h"


int set_ctl_vars(OpusEncoder *enc , int bitrate){
        
    printf("Opus Version = %s\n" , opus_get_version_string());
    
    int err;
    
    err = opus_encoder_ctl(enc, OPUS_SET_BITRATE(bitrate));
    if(err < 0){
        printf("failed to set bitrate: %s\n", opus_strerror(err));
        return 0;
    }
    
    err = opus_encoder_ctl(enc, OPUS_SET_BANDWIDTH(OPUS_BANDWIDTH_FULLBAND));
    if(err < 0){
        printf("faild to set bandwith: %s \n", opus_strerror(err));
        return 0;
    }
    
    err = opus_encoder_ctl(enc, OPUS_SET_APPLICATION(OPUS_APPLICATION_VOIP));
    if(err < 0){
        printf("faild to set application: %s \n", opus_strerror(err));
        return 0;
    }
    
    /*err = opus_encoder_ctl(enc, OPUS_SET_COMPLEXITY(10));
    if(err < 0){
        printf("faild to set complexity: %s \n", opus_strerror(err));
        return 0;
    }
    
    err = opus_encoder_ctl(enc, OPUS_SET_VBR(1));
    if(err < 0){
        printf("faild to set VBR %s \n", opus_strerror(err));
        return 0;
    }
    
    err = opus_encoder_ctl(enc, OPUS_SET_VBR_CONSTRAINT(1));
    if(err < 0){
        printf("faild to set VBR %s \n", opus_strerror(err));
        return 0;
    }
    
    err = opus_encoder_ctl(enc, OPUS_SET_LSB_DEPTH(14));
    if(err < 0){
        printf("faild to set LSB Depth: %s \n", opus_strerror(err));
        return 0;
    }
    
    err = opus_encoder_ctl(enc, OPUS_SET_FORCE_CHANNELS(1));
    if(err < 0){
        printf("faild to set VBR %s \n", opus_strerror(err));
        return 0;
    }
    
    err = opus_encoder_ctl(enc, OPUS_SET_DTX(1));
    if(err < 0){
        printf("faild to set DTX %s \n", opus_strerror(err));
        return 0;
    }
    
    err = opus_encoder_ctl(enc, OPUS_SET_PACKET_LOSS_PERC(1));
    if(err < 0){
        printf("faild to set packet loss: %s \n", opus_strerror(err));
        return 0;
    }*/
    
    err = opus_encoder_ctl(enc, OPUS_SET_EXPERT_FRAME_DURATION(OPUS_FRAMESIZE_60_MS));
    if(err < 0){
        printf("faild to set frame duration: %s \n", opus_strerror(err));
        return 0;
    }
    
    err = opus_encoder_ctl(enc, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
    if(err < 0){
        printf("faild to set voice signal: %s \n", opus_strerror(err));
        return 0;
    }
    
    printf("Version %s\n", opus_get_version_string());
    
    return 1;
}
