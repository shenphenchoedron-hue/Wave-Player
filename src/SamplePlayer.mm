#import "SamplePlayer.h"

#import <AVFoundation/AVFoundation.h>
#include <algorithm>
#include <cmath>
#include <cstring>

@interface SampleVoice : NSObject
@property (nonatomic, strong) AVAudioPlayerNode *player;
@property (nonatomic, strong) AVAudioUnitTimePitch *pitchUnit;
@property (nonatomic, strong) AVAudioPCMBuffer *buffer;
@property (nonatomic, strong) NSUUID *identifier;
@property (nonatomic, assign) NSInteger midiNote;
@property (nonatomic, strong, nullable) dispatch_source_t fadeTimer;
@end

@implementation SampleVoice
@end

@interface SamplePlayer ()
@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) AVAudioPCMBuffer *sampleBuffer;
@property (nonatomic, strong) AVAudioFormat *sampleFormat;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, SampleVoice *> *voicesById;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSUUID *> *voiceIdByMidi;
@property (nonatomic, assign) BOOL engineRunning;
- (AVAudioPCMBuffer *)bufferByReadingFile:(AVAudioFile *)file
                             targetFormat:(AVAudioFormat *)targetFormat
                                    error:(NSError * _Nullable * _Nullable)error;
@end

@implementation SamplePlayer

- (instancetype)init {
    self = [super init];
    if (self) {
        _engine = [[AVAudioEngine alloc] init];
        _voicesById = [NSMutableDictionary dictionary];
        _voiceIdByMidi = [NSMutableDictionary dictionary];
        _baseMIDINote = 60; // middle C default
        _fadeDuration = 0.01; // 10 ms fade
    }
    return self;
}

- (BOOL)hasLoadedSample {
    return self.sampleBuffer != nil;
}

- (BOOL)loadSampleAtURL:(NSURL *)url error:(NSError * _Nullable * _Nullable)error {
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:error];
    if (!file) {
        return NO;
    }

    AVAudioFormat *sourceFormat = file.processingFormat;
    AVAudioChannelCount channelCount = MAX(sourceFormat.channelCount, (AVAudioChannelCount)1);
    AVAudioFormat *targetFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                                  sampleRate:sourceFormat.sampleRate
                                                                     channels:channelCount
                                                                  interleaved:NO];
    if (!targetFormat) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                         code:-1
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Failed to create audio format for sample." }];
        }
        return NO;
    }

    AVAudioPCMBuffer *buffer = [self bufferByReadingFile:file
                                            targetFormat:targetFormat
                                                   error:error];
    if (!buffer) {
        return NO;
    }

    [self stopAllVoices];

    self.sampleBuffer = buffer;
    self.sampleFormat = buffer.format;

    if (!self.engineRunning) {
        NSError *engineError = nil;
        if (![self.engine startAndReturnError:&engineError]) {
            if (error) {
                *error = engineError;
            }
            return NO;
        }
        self.engineRunning = YES;
    }

    return YES;
}

- (NSUUID * _Nullable)playMIDINote:(NSInteger)midiNote {
    if (!self.sampleBuffer) {
        return nil;
    }

    AVAudioPlayerNode *player = [[AVAudioPlayerNode alloc] init];
    AVAudioUnitTimePitch *pitchUnit = [[AVAudioUnitTimePitch alloc] init];
    pitchUnit.pitch = (midiNote - self.baseMIDINote) * 100.0; // cents
    pitchUnit.rate = 1.0;

    [self.engine attachNode:player];
    [self.engine attachNode:pitchUnit];
    [self.engine connect:player to:pitchUnit format:self.sampleFormat];
    [self.engine connect:pitchUnit to:self.engine.mainMixerNode format:nil];
    [self.engine prepare];

    AVAudioPCMBuffer *buffer = [self fadedBufferFrom:self.sampleBuffer fadeSeconds:self.fadeDuration];
    if (!buffer) {
        return nil;
    }

    SampleVoice *voice = [[SampleVoice alloc] init];
    voice.player = player;
    voice.pitchUnit = pitchUnit;
    voice.buffer = buffer;
    voice.midiNote = midiNote;
    voice.identifier = [NSUUID UUID];

    NSNumber *key = @(midiNote);
    NSUUID *existingId = self.voiceIdByMidi[key];
    if (existingId) {
        SampleVoice *existing = self.voicesById[existingId];
        if (existing) {
            [self stopVoice:existing immediately:NO];
        }
    }

    __weak SamplePlayer *weakSelf = self;
    __weak SampleVoice *weakVoice = voice;
    [player scheduleBuffer:buffer atTime:nil options:0 completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf cleanupVoice:weakVoice];
        });
    }];

    player.volume = 1.0f;
    [player play];
    self.voicesById[voice.identifier] = voice;
    self.voiceIdByMidi[key] = voice.identifier;
    return voice.identifier;
}

- (void)stopMIDINote:(NSInteger)midiNote {
    NSNumber *key = @(midiNote);
    NSUUID *voiceId = self.voiceIdByMidi[key];
    SampleVoice *voice = self.voicesById[voiceId];
    if (voice) {
        [self stopVoice:voice immediately:NO];
    }
}

- (void)stopVoice:(SampleVoice *)voice immediately:(BOOL)immediate {
    if (!voice) {
        return;
    }

    if (voice.fadeTimer) {
        dispatch_source_cancel(voice.fadeTimer);
        voice.fadeTimer = nil;
    }

    if (immediate || self.fadeDuration <= 0.0) {
        [voice.player stop];
        [self cleanupVoice:voice];
        return;
    }

    [self fadeOutVoice:voice completion:^{
        [voice.player stop];
        [self cleanupVoice:voice];
    }];
}

- (void)cleanupVoice:(SampleVoice *)voice {
    if (!voice) {
        return;
    }

    NSUUID *voiceId = voice.identifier;
    if (!voiceId) {
        return;
    }

    SampleVoice *current = self.voicesById[voiceId];
    if (current != voice) {
        return;
    }

    if (voice.fadeTimer) {
        dispatch_source_cancel(voice.fadeTimer);
        voice.fadeTimer = nil;
    }

    [self.engine detachNode:voice.player];
    [self.engine detachNode:voice.pitchUnit];
    [self.voicesById removeObjectForKey:voiceId];

    NSNumber *key = @(voice.midiNote);
    if ([self.voiceIdByMidi[key] isEqual:voiceId]) {
        [self.voiceIdByMidi removeObjectForKey:key];
    }
}

- (void)fadeOutVoice:(SampleVoice *)voice completion:(dispatch_block_t)completion {
    if (!voice.player) {
        if (completion) {
            completion();
        }
        return;
    }

    const NSUInteger steps = 8;
    NSTimeInterval duration = MAX(self.fadeDuration, 0.0);
    if (duration == 0.0 || steps == 0) {
        voice.player.volume = 0.0f;
        if (completion) {
            completion();
        }
        return;
    }

    __block NSUInteger step = 0;
    float initialVolume = voice.player.volume;
    dispatch_queue_t queue = dispatch_get_main_queue();
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    voice.fadeTimer = timer;
    uint64_t interval = (uint64_t)((duration / (double)steps) * NSEC_PER_SEC);
    if (interval == 0) {
        interval = 1;
    }
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), interval, interval / 4);
    dispatch_source_set_event_handler(timer, ^{
        float progress = (float)(step + 1) / (float)steps;
        voice.player.volume = std::max(0.0f, initialVolume * (1.0f - progress));
        step++;
        if (step >= steps) {
            dispatch_source_cancel(timer);
            voice.fadeTimer = nil;
            voice.player.volume = 0.0f;
            if (completion) {
                completion();
            }
        }
    });
    dispatch_source_set_cancel_handler(timer, ^{
        voice.fadeTimer = nil;
    });
    dispatch_resume(timer);
}

- (AVAudioPCMBuffer *)fadedBufferFrom:(AVAudioPCMBuffer *)source fadeSeconds:(NSTimeInterval)seconds {
    if (!source) {
        return nil;
    }

    AVAudioFrameCount frameLength = source.frameLength;
    if (frameLength == 0) {
        return nil;
    }

    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:source.format frameCapacity:frameLength];
    buffer.frameLength = frameLength;

    NSUInteger channelCount = source.format.channelCount;
    double sampleRate = source.format.sampleRate;
    AVAudioFrameCount fadeSamples = (AVAudioFrameCount)(seconds * sampleRate);
    if (fadeSamples * 2 > frameLength) {
        fadeSamples = frameLength / 2;
    }
    if (fadeSamples == 0 && seconds > 0.0) {
        fadeSamples = MIN((AVAudioFrameCount)1, frameLength);
    }

    for (NSUInteger channel = 0; channel < channelCount; ++channel) {
        float *destination = buffer.floatChannelData ? buffer.floatChannelData[channel] : nullptr;
        const float *sourceData = source.floatChannelData ? source.floatChannelData[channel] : nullptr;
        if (!destination || !sourceData) {
            return nil;
        }

        memcpy(destination, sourceData, sizeof(float) * frameLength);
        for (AVAudioFrameCount i = 0; i < fadeSamples; ++i) {
            float gain = (float)i / (float)fadeSamples;
            destination[i] *= gain;
        }
        for (AVAudioFrameCount i = 0; i < fadeSamples; ++i) {
            AVAudioFrameCount index = frameLength - 1 - i;
            float gain = (float)i / (float)fadeSamples;
            destination[index] *= (1.0f - gain);
        }
    }

    return buffer;
}

- (void)stopAllVoices {
    NSArray<SampleVoice *> *voices = [[self.voicesById allValues] copy];
    for (SampleVoice *voice in voices) {
        [self stopVoice:voice immediately:YES];
    }
    [self.voicesById removeAllObjects];
    [self.voiceIdByMidi removeAllObjects];
}

- (AVAudioPCMBuffer *)bufferByReadingFile:(AVAudioFile *)file
                             targetFormat:(AVAudioFormat *)targetFormat
                                    error:(NSError * _Nullable * _Nullable)error {
    if (!file || !targetFormat) {
        return nil;
    }

    AVAudioFormat *sourceFormat = file.processingFormat;
    AVAudioFrameCount sourceFrameCount = (AVAudioFrameCount)file.length;

    if (sourceFrameCount == 0) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                         code:-1
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Sample file contains no audio frames." }];
        }
        return nil;
    }

    if ([sourceFormat isEqual:targetFormat]) {
        file.framePosition = 0;
        AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:sourceFormat
                                                                   frameCapacity:sourceFrameCount];
        if (![file readIntoBuffer:buffer error:error]) {
            return nil;
        }
        buffer.frameLength = sourceFrameCount;
        if (buffer.frameLength == 0) {
            if (error) {
                *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                             code:-1
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Sample file contains no audio frames." }];
            }
            return nil;
        }
        return buffer;
    }

    double ratio = targetFormat.sampleRate / MAX(sourceFormat.sampleRate, 1.0);
    AVAudioFrameCount targetCapacity = (AVAudioFrameCount)ceil(sourceFrameCount * ratio) + targetFormat.channelCount;
    AVAudioPCMBuffer *converted = [[AVAudioPCMBuffer alloc] initWithPCMFormat:targetFormat
                                                                frameCapacity:targetCapacity];

    if (!converted) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                         code:-1
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Failed to allocate audio buffer for conversion." }];
        }
        return nil;
    }

    AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:sourceFormat toFormat:targetFormat];
    if (!converter) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                         code:-1
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Unable to create audio converter." }];
        }
        return nil;
    }

    file.framePosition = 0;
    __block AVAudioFramePosition framesRead = 0;
    NSError *conversionError = nil;
    NSError __strong **strongError = error;
    BOOL success = [converter convertToBuffer:converted
                                        error:&conversionError
                        withInputFromBlock:^AVAudioBuffer * _Nullable(AVAudioPacketCount inNumberOfPackets,
                                                                     AVAudioConverterInputStatus *outStatus) {
        AVAudioFramePosition remaining = sourceFrameCount - framesRead;
        if (remaining <= 0) {
            *outStatus = AVAudioConverterInputStatus_EndOfStream;
            return nil;
        }

        AVAudioFrameCount framesToRead = (AVAudioFrameCount)MIN((AVAudioFramePosition)inNumberOfPackets, remaining);
        AVAudioPCMBuffer *inputBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:sourceFormat frameCapacity:framesToRead];
        if (!inputBuffer) {
            *outStatus = AVAudioConverterInputStatus_NoDataNow;
            return nil;
        }

        NSError *readError = nil;
        if (![file readIntoBuffer:inputBuffer frameCount:framesToRead error:&readError]) {
            if (strongError && readError) {
                *strongError = readError;
            }
            *outStatus = AVAudioConverterInputStatus_NoDataNow;
            return nil;
        }

        inputBuffer.frameLength = framesToRead;
        framesRead += framesToRead;
        *outStatus = AVAudioConverterInputStatus_HaveData;
        return inputBuffer;
    }];

    if (!success) {
        if (error) {
            *error = conversionError ?: [NSError errorWithDomain:NSOSStatusErrorDomain
                                                            code:-1
                                                        userInfo:@{ NSLocalizedDescriptionKey : @"Audio conversion failed." }];
        }
        return nil;
    }

    if (converted.frameLength == 0) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                         code:-1
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Converted buffer has no audio data." }];
        }
        return nil;
    }

    return converted;
}

@end
