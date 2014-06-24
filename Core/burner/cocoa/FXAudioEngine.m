/*****************************************************************************
 **
 ** FinalBurn X: Port of FinalBurn to OS X
 ** https://github.com/pokebyte/FinalBurnX
 ** Copyright (C) 2014 Akop Karapetyan
 **
 ** Sound engine based on SDL_audio:
 **
 **   SDL - Simple DirectMedia Layer
 **   Copyright (C) 1997-2012 Sam Lantinga (slouken@libsdl.org)
 **
 ** This program is free software; you can redistribute it and/or modify
 ** it under the terms of the GNU General Public License as published by
 ** the Free Software Foundation; either version 2 of the License, or
 ** (at your option) any later version.
 **
 ** This program is distributed in the hope that it will be useful,
 ** but WITHOUT ANY WARRANTY; without even the implied warranty of
 ** MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 ** GNU General Public License for more details.
 **
 ** You should have received a copy of the GNU General Public License
 ** along with this program; if not, write to the Free Software
 ** Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 **
 ******************************************************************************
 */
#import "FXAudioEngine.h"

static OSStatus audioCallback(void *inRefCon,
                              AudioUnitRenderActionFlags *ioActionFlags,
                              const AudioTimeStamp *inTimeStamp,
                              UInt32 inBusNumber, UInt32 inNumberFrames,
                              AudioBufferList *ioData);

@interface FXAudioEngine ()

- (void)renderSoundToStream:(AudioBufferList *)ioData;

@end

@implementation FXAudioEngine

@synthesize delegate = _delegate;

- (void)dealloc
{
    if (isReady) {
        OSStatus result;
        struct AURenderCallbackStruct callback;
        
        result = AudioOutputUnitStop(outputAudioUnit);
        
        callback.inputProc = 0;
        callback.inputProcRefCon = 0;
        result = AudioUnitSetProperty(outputAudioUnit,
                                      kAudioUnitProperty_SetRenderCallback,
                                      kAudioUnitScope_Input, 0, &callback,
                                      sizeof(callback));
        
        result = CloseComponent(outputAudioUnit); // FIXME: deprec
        isReady = NO;
    }
    
    free(__buffer);
    __buffer = NULL;
    
#ifdef DEBUG
    NSLog(@"audioEngine/destroyed");
#endif
}

#pragma mark - Private Methods

- (id)initWithSampleRate:(NSUInteger)sampleRate
                channels:(NSUInteger)channels
                 samples:(NSUInteger)samples
          bitsPerChannel:(UInt32)bitsPerChannel
{
    if ((self = [super init])) {
        isPaused = NO;
        isReady = NO;
        
        __buffer = NULL;
        
        OSStatus result = noErr;
        Component comp;
        ComponentDescription desc;
        struct AURenderCallbackStruct callback;
        AudioStreamBasicDescription requestedDesc;
        
        // Setup a AudioStreamBasicDescription with the requested format
        requestedDesc.mFormatID = kAudioFormatLinearPCM;
        requestedDesc.mFormatFlags = kLinearPCMFormatFlagIsPacked;
        requestedDesc.mChannelsPerFrame = (UInt32)channels;
        requestedDesc.mSampleRate = sampleRate;
        
        requestedDesc.mBitsPerChannel = (UInt32)bitsPerChannel;
        requestedDesc.mFormatFlags |= kLinearPCMFormatFlagIsSignedInteger;
        
        requestedDesc.mFramesPerPacket = 1;
        requestedDesc.mBytesPerFrame = requestedDesc.mBitsPerChannel * requestedDesc.mChannelsPerFrame / 8;
        requestedDesc.mBytesPerPacket = requestedDesc.mBytesPerFrame * requestedDesc.mFramesPerPacket;
        
        // Locate the default output audio unit
        desc.componentType = kAudioUnitType_Output;
        desc.componentSubType = kAudioUnitSubType_DefaultOutput;
        desc.componentManufacturer = kAudioUnitManufacturer_Apple;
        desc.componentFlags = 0;
        desc.componentFlagsMask = 0;
        
        comp = FindNextComponent(NULL, &desc); // FIXME: deprec
        if (comp != NULL) {
            // Open & initialize the default output audio unit
            result = OpenAComponent(comp, &outputAudioUnit); // FIXME: deprec
            if (result == noErr) {
                result = AudioUnitInitialize(outputAudioUnit);
                if (result == noErr) {
                    // Set the input format of the audio unit
                    result = AudioUnitSetProperty(outputAudioUnit,
                                                  kAudioUnitProperty_StreamFormat,
                                                  kAudioUnitScope_Input, 0, &requestedDesc,
                                                  sizeof(requestedDesc));
                    
                    if (result == noErr) {
                        // Set the audio callback
                        callback.inputProc = audioCallback;
                        callback.inputProcRefCon = (__bridge void *)self;
                        result = AudioUnitSetProperty(outputAudioUnit,
                                                      kAudioUnitProperty_SetRenderCallback,
                                                      kAudioUnitScope_Input, 0, &callback,
                                                      sizeof(callback));
                        
                        if (result == noErr) {
                            __bufferSize = bitsPerChannel / 8;
                            __bufferSize *= channels;
                            __bufferSize *= samples;
                            __bufferOffset = __bufferSize;
                            __buffer = calloc(__bufferSize, 1);
                            
                            // Finally, start processing of the audio unit
                            result = AudioOutputUnitStart (outputAudioUnit);
                            if (result == noErr) {
                                isReady = YES;
                            }
                        }
                    }
                }
            }
        }
    }
    
#ifdef DEBUG
    NSLog(@"audioEngine/initialized");
#endif
    
    return self;
}

- (void)renderSoundToStream:(AudioBufferList *)ioData
{
    UInt32 remaining, len;
    AudioBuffer *abuf;
    void *ptr;
    
    if (isPaused || !isReady) {
        for (int i = 0; i < ioData->mNumberBuffers; i++) {
            abuf = &ioData->mBuffers[i];
            memset(abuf->mData, 0, abuf->mDataByteSize);
        }
        
        return;
    }
    
    for (int i = 0; i < ioData->mNumberBuffers; i++) {
        abuf = &ioData->mBuffers[i];
        remaining = abuf->mDataByteSize;
        ptr = abuf->mData;
        
        while (remaining > 0) {
            if (__bufferOffset >= __bufferSize) {
                memset(__buffer, 0, __bufferSize);
                
                @synchronized(self) {
                    [[self delegate] mixSoundFromBuffer:__buffer
                                                  bytes:__bufferSize];
                }
                
                __bufferOffset = 0;
            }
            
            len = __bufferSize - __bufferOffset;
            if (len > remaining) {
                len = remaining;
            }
            
            memcpy(ptr, __buffer + __bufferOffset, len);
            ptr = (char *)ptr + len;
            remaining -= len;
            __bufferOffset += len;
        }
    }
}

#pragma mark - Public Methods

- (void)pause
{
    if (!isPaused) {
        isPaused = YES;
    }
}

- (void)resume
{
    if (isPaused) {
        isPaused = NO;
    }
}

#pragma mark - Miscellaneous Callbacks

static OSStatus audioCallback(void *inRefCon,
                              AudioUnitRenderActionFlags *ioActionFlags,
                              const AudioTimeStamp *inTimeStamp,
                              UInt32 inBusNumber, UInt32 inNumberFrames,
                              AudioBufferList *ioData)
{
    FXAudioEngine *sound = (__bridge FXAudioEngine *)inRefCon;
    [sound renderSoundToStream:ioData];
    
    return 0;
}

@end