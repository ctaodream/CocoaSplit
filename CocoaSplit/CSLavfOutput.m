//
//  FFMpegTask.m
//  H264Streamer
//
//  Created by Zakk on 9/4/12.
//

#import "CSLavfOutput.h"
#import <CoreMedia/CoreMedia.h>
#import "libavformat/avformat.h"
#import "CapturedFrameData.h"
#import "CaptureController.h"
#import "libavutil/opt.h"
#import <sys/types.h>
#import <sys/stat.h>
#include "libavformat/avformat.h"
#include "libavformat/avio.h"

#import <stdio.h>
int ffurl_get_file_handle(struct URLContext *);

@interface CSLavfOutput ()
{
    AVFormatContext *_av_fmt_ctx;
    AVStream *_av_video_stream;
    AVStream *_av_audio_stream;
    
    char *_audio_extradata;
    size_t _audio_extradata_size;
    
    int _input_framecnt;
    int _pending_frame_count;
    int _pending_frame_size;
    int _consecutive_dropped_frames;
    int _dropped_frames;
    
    NSMutableArray *_frameQueue;
    dispatch_semaphore_t _frameSemaphore;
    dispatch_queue_t _frameConsumerQueue;
    bool _close_flag;
}

@property (assign) int width;
@property (assign) int height;
@property (assign) BOOL init_done;

@end

@implementation CSLavfOutput




-(NSUInteger)frameQueueSize
{
    NSUInteger ret = 0;
    @synchronized (self) {
        ret = _frameQueue.count;
    }
    
    return ret;
}


-(void)clearFrameQueue
{
    @synchronized (self) {
        [_frameQueue removeAllObjects];
        self.buffered_frame_size = 0;
    }
}


-(CapturedFrameData *)consumeframeData
{
    CapturedFrameData *retData = nil;
    
    @synchronized (self) {
        if (_frameQueue.count > 0)
        {
            retData = [_frameQueue objectAtIndex:0];
            [_frameQueue removeObjectAtIndex:0];
            self.buffered_frame_size -= [retData encodedDataLength];
        }
    }
    
    return retData;
}


-(void)startConsumerThread
{
    if (!_frameConsumerQueue)
    {
        _frameConsumerQueue = dispatch_queue_create("FFMpeg consumer", DISPATCH_QUEUE_SERIAL);
        
        dispatch_async(_frameConsumerQueue, ^{
            
            while (1)
            {
                @autoreleasepool {
                    
                    @synchronized (self) {
                        if (self->_close_flag)
                        {
                            
                            [self _internal_stopProcess];
                            break;
                        }
                    }
                    
                    CapturedFrameData *useData = [self consumeframeData];
                    if (!useData)
                    {
                        dispatch_semaphore_wait(self->_frameSemaphore, DISPATCH_TIME_FOREVER);
                    } else {
                        [self writeEncodedData:useData];
                    }
                }
            }
            
        });
    }
}


-(bool)queueFramedata:(CapturedFrameData *)frameData
{
    if (!_frameConsumerQueue)
    {
        [self startConsumerThread];
    }
    
    @synchronized (self) {
        [_frameQueue addObject:frameData];
        self.buffered_frame_size += [frameData encodedDataLength];
        dispatch_semaphore_signal(_frameSemaphore);
    }
    return YES;
}



int readAudioTagLength(char **buffer)
{
    int length = 0;
    int cnt =4;
    
    while(cnt--)
    {
        int c = *(*buffer)++;
        
        length = (length << 7) | (c & 0x7f);
        if (!(c & 0x80))
            break;
    }
    return length;
}


-(NSUInteger)buffered_frame_count
{
    return [self frameQueueSize];
}


int readAudioTag(char **buffer, int *tag)
{
    
    *tag = *(*buffer)++;
    return readAudioTagLength(buffer);
    
}



void getAudioExtradata(char *cookie, char **buffer, size_t *size)
{
    char *esds = cookie;
    
    int tag, length;
    
    *size = 0;
    
    readAudioTag(&esds, &tag);
    esds += 2;
    if (tag == 0x03)
        esds++;
    
    readAudioTag(&esds, &tag);
    
    
    if (tag == 0x04) {
        esds++;
        esds++;
        esds += 3;
        esds += 4;
        esds += 4;
        
        length = readAudioTag(&esds, &tag);
        if (tag == 0x05)
        {
            *buffer = calloc(1, length + 8);
            if (*buffer)
            {
                memcpy(*buffer, esds, length);
                *size = length;
                
            }
            
        }
    }
}




-(void) extractAudioCookie:(CMSampleBufferRef)theBuffer
{
    CMAudioFormatDescriptionRef audio_fmt;
    
    
    audio_fmt = CMSampleBufferGetFormatDescription(theBuffer);
    if (!audio_fmt)
    {
        return;
    }
    
    void *audio_tmp;
    audio_tmp = (char *)CMAudioFormatDescriptionGetMagicCookie(audio_fmt, &_audio_extradata_size);
    if (audio_tmp)
    {
        getAudioExtradata(audio_tmp, &_audio_extradata, &_audio_extradata_size);
    }
    
}


-(BOOL) writeEncodedData:(CapturedFrameData *)frameDataIn
{
    
    
    CapturedFrameData *frameData = frameDataIn;
    
    if (!_audio_extradata && [frameData.audioSamples count] > 0)
    {
        
        CMSampleBufferRef audioSample = (__bridge CMSampleBufferRef)[frameData.audioSamples objectAtIndex:0];
        [self extractAudioCookie:audioSample];
    }
    
    if (!_av_video_stream && _audio_extradata)
    {
        
        if ([self createAVFormatOut:frameData.encodedSampleBuffer])
        {
            [self initStatsValues];
        } else {
            return NO;
        }
    }
    
    if (!_av_video_stream || !_av_audio_stream)
    {
        //This is a lie. We probably have only received video frames and are waiting for audio. Just pretend we did something.
        return YES;
    }
    
    
    //If we made it here, we have all the metadata and av* stuff created, so start sending data.
    
    for (id object in frameData.audioSamples)
    {
        CMSampleBufferRef audioSample = (__bridge CMSampleBufferRef)object;
        
        
        [self writeAudioSampleBuffer:audioSample presentationTimeStamp:CMSampleBufferGetOutputPresentationTimeStamp(audioSample)];
        
        //CFRelease(audioSample);
    }
    
    BOOL  ret_status = YES;
    
    if (frameData.encodedSampleBuffer)
    {
        
        ret_status = [self writeVideoSampleBuffer:frameData];
    }
    
    return ret_status;
}

-(BOOL) writeAudioSampleBuffer:(CMSampleBufferRef)theBuffer presentationTimeStamp:(CMTime)pts
{
    
    
    CFRetain(theBuffer);

    BOOL ret_val = YES;

    if (_av_audio_stream && (self.init_done == YES))
    {
        
            CMBlockBufferRef blockBufferRef = CMSampleBufferGetDataBuffer(theBuffer);
            size_t buffer_length;
            size_t offset_length;
            char *sampledata;
        
            AVPacket pkt;
        
            av_init_packet(&pkt);
        
        
            pkt.stream_index = _av_audio_stream->index;
        
            CMBlockBufferGetDataPointer(blockBufferRef, 0, &offset_length, &buffer_length, &sampledata);
        
        
        
            pkt.data = (uint8_t *)sampledata;
        
            pkt.size = (int)buffer_length;
            //pkt.destruct = NULL;
            
        
        
            pkt.pts = av_rescale_q(pts.value, (AVRational) {1.0, pts.timescale}, _av_audio_stream->time_base);
        pkt.dts = pkt.pts;
        



        
        
            
            if (av_interleaved_write_frame(_av_fmt_ctx, &pkt) < 0)
            {
                ret_val = NO;
                //[self stopProcess];
            }
            //dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                CFRelease(theBuffer);
            //});
    }
    
    return ret_val;
}

-(void) setVideoFormatOptions:(AVFormatContext *)ctx
{
    
    
    ctx->avoid_negative_ts = AVFMT_AVOID_NEG_TS_MAKE_ZERO;
    
    
    AVOutputFormat *ofmt = ctx->oformat;
    
    if (!ofmt)
    {
        return;
    }
    
    const char *fmt_name = ofmt->name;
    
    if (!strcasecmp(fmt_name, "mmmmmov"))
    {
        av_opt_set_int(ctx->priv_data, "frag_duration", 10000000, 0);
    } else if (!strcasecmp(fmt_name, "segment")) {
        av_opt_set(ctx->priv_data, "reset_timestamps", "1", AV_OPT_SEARCH_CHILDREN);
    }
}


-(bool) createAVFormatOut:(CMSampleBufferRef)theBuffer
{
 
    NSLog(@"Creating output format %@ DESTINATION %@", self.stream_format, self.stream_output);
    AVOutputFormat *av_out_fmt;
    
    int avErr = 0;
    
    if (self.stream_format) {
        avErr = avformat_alloc_output_context2(&_av_fmt_ctx, NULL, [self.stream_format UTF8String], [self.stream_output UTF8String]);
    } else {
        avErr = avformat_alloc_output_context2(&_av_fmt_ctx, NULL, NULL, [self.stream_output UTF8String]);
    }
        
    if (!_av_fmt_ctx)
    {
        return NO;
    }
    
    
    [self setVideoFormatOptions:_av_fmt_ctx];
    
    av_out_fmt = _av_fmt_ctx->oformat;
    
    _av_video_stream = avformat_new_stream(_av_fmt_ctx, 0);
    
    if (!_av_video_stream)
    {
        return NO;
    }
    
    
    AVCodecParameters *c_ctx = _av_video_stream->codecpar;
    _av_audio_stream = avformat_new_stream(_av_fmt_ctx, 0);
    
    if (!_av_audio_stream)
    {
        return NO;
    }
    
    AVCodecParameters *a_ctx = _av_audio_stream->codecpar;
    //AVCodecContext *a_ctx = _av_audio_stream->codec;
    
    
    a_ctx->codec_type = AVMEDIA_TYPE_AUDIO;
    a_ctx->codec_id = AV_CODEC_ID_AAC;
    
    /*_av_audio_stream->time_base.num = 100000;
    _av_audio_stream->time_base.den = self.framerate*100000;
     */
    
    _av_audio_stream->time_base.num = 1;
    _av_audio_stream->time_base.den = self.samplerate;
    
    a_ctx->sample_rate = self.samplerate;
    a_ctx->bit_rate = self.audio_bitrate;
    a_ctx->channels = 2;
    a_ctx->extradata = (unsigned char *)_audio_extradata;
    a_ctx->extradata_size = (int)_audio_extradata_size;
    a_ctx->frame_size = 1024;
    
    //a_ctx->frame_size = (_samplerate * 2 * 2) / _framerate;
    
    if (theBuffer)
    {
        CMFormatDescriptionRef fmt;
        CFDictionaryRef atoms;
        CFStringRef avccKey;
        CFDataRef avcc_data;
        CFIndex avcc_size;
        
        CMVideoDimensions avc_dimensions;
        
        fmt = CMSampleBufferGetFormatDescription(theBuffer);
        avc_dimensions = CMVideoFormatDescriptionGetDimensions(fmt);
        self.width = avc_dimensions.width;
        self.height = avc_dimensions.height;
        CMVideoCodecType videoCodec = CMVideoFormatDescriptionGetCodecType(fmt);
        
        
        atoms = CMFormatDescriptionGetExtension(fmt, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms);
        avccKey = CFSTR("avcC");
        if (atoms)
        {
            
            avcc_data = CFDictionaryGetValue(atoms, avccKey);
            if (!avcc_data)
            {
                //Try the HEVC atom key
                avccKey = CFSTR("hvcC");
                avcc_data = CFDictionaryGetValue(atoms, avccKey);
                if (avcc_data)
                {
                    c_ctx->codec_tag = MKTAG('h', 'v', 'c', '1');

                }
            }
            
            if (!avcc_data)
            {
                return NO;
            }
            avcc_size = CFDataGetLength(avcc_data);
            c_ctx->extradata = av_malloc(avcc_size);
    
            CFDataGetBytes(avcc_data, CFRangeMake(0,avcc_size), c_ctx->extradata);
    
            c_ctx->extradata_size = (int)avcc_size;
        }
        c_ctx->codec_type = AVMEDIA_TYPE_VIDEO;
        switch(videoCodec)
        {
            case kCMVideoCodecType_H264:
                c_ctx->codec_id = AV_CODEC_ID_H264;
                break;
            case kCMVideoCodecType_HEVC:
                c_ctx->codec_id = AV_CODEC_ID_HEVC;
                break;
            case kCMVideoCodecType_AppleProRes422:
            case kCMVideoCodecType_AppleProRes4444:
            case kCMVideoCodecType_AppleProRes422HQ:
            case kCMVideoCodecType_AppleProRes422LT:
            case kCMVideoCodecType_AppleProRes422Proxy:
                c_ctx->codec_id = AV_CODEC_ID_PRORES;
                break;
            default:
                c_ctx->codec_id = AV_CODEC_ID_H264; //Whatever
        }
    }


    c_ctx->width = self.width;
    c_ctx->height = self.height;

    
    av_dump_format(_av_fmt_ctx, 0, [self.stream_output UTF8String], 1);
    
    if (!(av_out_fmt->flags & AVFMT_NOFILE))
    {
        int av_err;
        if ((av_err = avio_open(&_av_fmt_ctx->pb, [self.stream_output UTF8String], AVIO_FLAG_WRITE)) < 0)
        {
            NSString *open_err = [self av_error_nsstring:av_err ];

            
            NSLog(@"AVIO_OPEN failed REASON %@", open_err);
            _av_fmt_ctx->pb = NULL;
            self.errored = YES;
            [self stopProcess];
            return NO;
        }
    }
        if (_av_fmt_ctx == NULL || avformat_write_header(_av_fmt_ctx, NULL) < 0)
    {
 
        NSLog(@"AVFORMAT_WRITE_HEADER failed");
        self.errored = YES;
        [self stopProcess];
        return NO;
    }
    
    self.init_done = YES;
    return YES;
}

-(void) initStatsValues
{
    self.output_framecnt = 0;
    self.output_bytes = 0;
    self.buffered_frame_size = 0;
}




-(BOOL) writeVideoSampleBuffer:(CapturedFrameData *)frameData
{
    
    if (!frameData || !frameData.encodedSampleBuffer)
    {
        return NO;
    }
    
    CFRetain(frameData.encodedSampleBuffer);
    
    
    
    
    CMSampleBufferRef theBuffer = frameData.encodedSampleBuffer;
    CMBlockBufferRef my_buffer;
    char *sampledata;
    size_t offset_length;
    size_t buffer_length;
    
    my_buffer = CMSampleBufferGetDataBuffer(theBuffer);
    
    
    AVPacket pkt;
    
    av_init_packet(&pkt);
    
    
    pkt.stream_index = _av_video_stream->index;
    
    CMBlockBufferGetDataPointer(my_buffer, 0, &offset_length, &buffer_length, &sampledata);
    
    pkt.data = (uint8_t *)sampledata;
    
    pkt.size = (int)buffer_length;
  
        
        
    pkt.dts = av_rescale_q(CMSampleBufferGetDecodeTimeStamp(theBuffer).value, (AVRational) {1.0, CMSampleBufferGetDecodeTimeStamp(theBuffer).
                timescale}, _av_video_stream->time_base);
        
    pkt.pts = av_rescale_q(CMSampleBufferGetPresentationTimeStamp(theBuffer).value, (AVRational) {1.0, CMSampleBufferGetPresentationTimeStamp(theBuffer).timescale}, _av_video_stream->time_base);

    
    if (pkt.dts == AV_NOPTS_VALUE)
    {
        pkt.dts = pkt.pts;
    }
    
    
    if (frameData.isKeyFrame)
    {
        pkt.flags |= AV_PKT_FLAG_KEY;
    }
    
    

    BOOL send_status = YES;
    
    if (av_interleaved_write_frame(_av_fmt_ctx, &pkt) < 0)
    {
        NSLog(@"VIDEO WRITE FRAME failed for %@", self.stream_output);
        send_status = NO;
        //[self stopProcess];
    } else {
        self.output_framecnt++;
        self.output_bytes += [frameData encodedDataLength];
    }

    CFRelease(theBuffer);
        
    return send_status;
        
  }





-(id)init
{
    
    self = [super init];
    self.init_done = NO;
    self.errored = NO;
    _close_flag = NO;
    
    _frameQueue = [NSMutableArray arrayWithCapacity:1000];
    _frameSemaphore = dispatch_semaphore_create(0);
    _pending_frame_size = 0;

    
    avformat_network_init();
    return self;
    
}


-(bool)stopProcess
{
    
    if (_frameConsumerQueue)
    {
        @synchronized (self) {
            _close_flag = YES;
            dispatch_semaphore_signal(_frameSemaphore);
        }
    } else {
        [self _internal_stopProcess];
    }
    
    return YES;
}



-(bool)_internal_stopProcess
{
    
    if (_av_fmt_ctx)
    {
        if (_av_fmt_ctx->pb && !self.errored)
        {
            av_write_trailer(_av_fmt_ctx);
        }
        
        avio_flush(_av_fmt_ctx->pb);
        
        avio_close(_av_fmt_ctx->pb);
        avformat_free_context(_av_fmt_ctx);
        
    }
    
    _av_fmt_ctx = NULL;
    _av_video_stream = NULL;
    _av_audio_stream = NULL;
    
    if (_audio_extradata)
    {
        //free(_audio_extradata);
        _audio_extradata = NULL;
    }
    return YES;
        
}

-(NSString *) av_error_nsstring:(int)av_err_num
{
    NSString *errstr = nil;
    
    
    char *av_err_str;
    
    av_err_str = malloc(AV_ERROR_MAX_STRING_SIZE);
    
    if (av_strerror(av_err_num, av_err_str, AV_ERROR_MAX_STRING_SIZE) < 0)
    {
        free(av_err_str);
        errstr = nil;
    } else {
        errstr = [[NSString alloc] initWithBytesNoCopy:av_err_str length:AV_ERROR_MAX_STRING_SIZE encoding:NSASCIIStringEncoding freeWhenDone:YES];
    }
    
    return errstr;
}


@end
