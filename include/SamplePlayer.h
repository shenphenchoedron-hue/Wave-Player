#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SamplePlayer : NSObject

@property (nonatomic, assign) NSInteger baseMIDINote; // default: 60 (C4)
@property (nonatomic, assign) NSTimeInterval fadeDuration; // seconds, default 0.01

- (BOOL)loadSampleAtURL:(NSURL *_Nonnull)url error:(NSError *__autoreleasing _Nullable *_Nullable)error;
- (NSUUID *_Nullable)playMIDINote:(NSInteger)midiNote;
- (BOOL)loadSampleAtURL:(NSURL *)url error:(NSError * _Nullable *)error;
- (NSUUID * _Nullable)playMIDINote:(NSInteger)midiNote;
- (void)stopMIDINote:(NSInteger)midiNote;
- (BOOL)hasLoadedSample;

@end

NS_ASSUME_NONNULL_END
