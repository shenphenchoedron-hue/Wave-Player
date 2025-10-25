#import "SamplePlayer.h"

#import <AVFoundation/AVFoundation.h>
#include <cstring>

@interface SampleVoice : NSObject
@property (nonatomic, strong) AVAudioPlayerNode *player;
@property (nonatomic, strong) AVAudioUnitTimePitch *pitchUnit;
@property (nonatomic, strong) AVAudioPCMBuffer *buffer;
@property (nonatomic, strong) NSUUID *identifier;
@property (nonatomic, assign) NSInteger midiNote;
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

- (BOOL)loadSampleAtURL:(NSURL *)url error:(NSError * _Nullable *)error {
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:error];
    if (!file) {
        return NO;
    }

    AVAudioFormat *processingFormat = file.processingFormat;
    AVAudioFrameCount frameCount = (AVAudioFrameCount)file.length;
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:processingFormat frameCapacity:frameCount];
    if (![file readIntoBuffer:buffer error:error]) {
        return NO;
    }
    buffer.frameLength = frameCount;

    [self stopAllVoices];

    self.sampleBuffer = buffer;
    self.sampleFormat = processingFormat;

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
    [self.engine connect:pitchUnit to:self.engine.mainMixerNode format:self.sampleFormat];

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

    __weak typeof(self) weakSelf = self;
    __weak SampleVoice *weakVoice = voice;
    [player scheduleBuffer:buffer atTime:nil options:0 completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf cleanupVoice:weakVoice];
        });
    }];

    [player setVolume:1.0f];
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

    if (immediate || self.fadeDuration <= 0.0) {
        [voice.player stop];
        [self cleanupVoice:voice];
        return;
    }

    [voice.player setVolume:0.0f fadeDuration:self.fadeDuration];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.fadeDuration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [voice.player stop];
        [self cleanupVoice:voice];
    });
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

    [self.engine detachNode:voice.player];
    [self.engine detachNode:voice.pitchUnit];
    [self.voicesById removeObjectForKey:voiceId];

    NSNumber *key = @(voice.midiNote);
    if ([self.voiceIdByMidi[key] isEqual:voiceId]) {
        [self.voiceIdByMidi removeObjectForKey:key];
    }
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

    for (NSUInteger channel = 0; channel < channelCount; ++channel) {
        float *destination = buffer.floatChannelData[channel];
        const float *sourceData = source.floatChannelData[channel];
        if (!destination || !sourceData) {
            continue;
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
}

@end
