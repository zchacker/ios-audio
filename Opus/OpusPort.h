//
//  OpusPort.h
//  Audio Chat
//
//  Created by Brown Diamond Tech on 7/27/24.
//

#ifndef OpusPort_h
#define OpusPort_h

#include <stdio.h>
#include "include/opus/opus_defines.h"
#include "include/opus/opus_multistream.h"
#include "include/opus/opus_projection.h"
#include "include/opus/opus_types.h"
#include "include/opus/opus.h"

int set_ctl_vars(OpusEncoder *enc, int bitrate);

#endif /* OpusPort_h */
