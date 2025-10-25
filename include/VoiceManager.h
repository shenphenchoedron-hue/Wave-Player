#pragma once

#include <array>
#include <cmath>
#include <mutex>
#include <vector>

class VoiceManager {
public:
    VoiceManager(const std::vector<float>& sampleData,
                 int sampleRate,
                 int channels,
                 int outputChannels,
                 int baseNote);

    void noteOn(int midiNote);
    void noteOff(int midiNote);
    void stopAll();

    void mix(float* output, int frameCount);

    int outputChannels() const { return outputChannels_; }

private:
    enum class Stage {
        Idle,
        Attack,
        Sustain,
        Release
    };

    struct Voice {
        Stage stage = Stage::Idle;
        int note = 0;
        double position = 0.0;
        double step = 1.0;
        float gain = 0.0f;
    };

    double computeStepFor(int midiNote) const;
    int findVoiceFor(int midiNote);
    int findFreeVoice();
    int stealVoice();
    void beginRelease(Voice& voice);

    void advanceEnvelope(Voice& voice);

    const std::vector<float>& sampleData_;
    int sampleRate_;
    int channels_;
    int outputChannels_;
    int baseNote_;
    int sampleFrames_;

    float attackIncrement_;
    float releaseIncrement_;

    static constexpr int kMaxVoices = 32;
    std::array<Voice, kMaxVoices> voices_{};
    std::mutex mutex_;
};

