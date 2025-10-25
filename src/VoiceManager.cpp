#include "VoiceManager.h"

#include <algorithm>
#include <limits>

namespace {
constexpr float kMinimumGain = 0.0001f;
}

VoiceManager::VoiceManager(const std::vector<float>& sampleData,
                           int sampleRate,
                           int channels,
                           int outputChannels,
                           int baseNote)
    : sampleData_(sampleData),
      sampleRate_(sampleRate),
      channels_(channels),
      outputChannels_(outputChannels),
      baseNote_(baseNote),
      sampleFrames_(static_cast<int>(sampleData.size() / static_cast<size_t>(channels))) {
    if (sampleFrames_ <= 0) {
        sampleFrames_ = 1;
    }
    const double attackSeconds = 0.01;  // 10 ms ramp-in.
    const double releaseSeconds = 0.05; // 50 ms ramp-out.
    attackIncrement_ = attackSeconds <= 0.0
                           ? 1.0f
                           : static_cast<float>(1.0 / (attackSeconds * static_cast<double>(sampleRate_)));
    releaseIncrement_ = releaseSeconds <= 0.0
                            ? 1.0f
                            : static_cast<float>(1.0 / (releaseSeconds * static_cast<double>(sampleRate_)));
    attackIncrement_ = std::clamp(attackIncrement_, 0.0f, 1.0f);
    releaseIncrement_ = std::clamp(releaseIncrement_, 0.0f, 1.0f);
}

void VoiceManager::noteOn(int midiNote) {
    std::lock_guard<std::mutex> lock(mutex_);

    int index = findFreeVoice();
    if (index < 0) {
        index = stealVoice();
    }

    int existing = findVoiceFor(midiNote);
    if (existing >= 0 && existing != index) {
        beginRelease(voices_[existing]);
    }

    Voice& voice = voices_[index];
    voice.stage = Stage::Attack;
    voice.note = midiNote;
    voice.position = 0.0;
    voice.step = computeStepFor(midiNote);
    voice.gain = 0.0f;
}

void VoiceManager::noteOff(int midiNote) {
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto& voice : voices_) {
        if (voice.stage != Stage::Idle && voice.note == midiNote) {
            beginRelease(voice);
        }
    }
}

void VoiceManager::stopAll() {
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto& voice : voices_) {
        voice.stage = Stage::Idle;
        voice.position = 0.0;
        voice.gain = 0.0f;
        voice.note = 0;
    }
}

void VoiceManager::mix(float* output, int frameCount) {
    std::fill(output, output + frameCount * outputChannels_, 0.0f);

    std::lock_guard<std::mutex> lock(mutex_);
    for (int frame = 0; frame < frameCount; ++frame) {
        float left = 0.0f;
        float right = 0.0f;

        for (auto& voice : voices_) {
            if (voice.stage == Stage::Idle) {
                continue;
            }

            size_t index0 = static_cast<size_t>(voice.position);
            if (index0 >= static_cast<size_t>(sampleFrames_)) {
                index0 = static_cast<size_t>(sampleFrames_ - 1);
                voice.position = static_cast<double>(sampleFrames_ - 1);
                beginRelease(voice);
            }

            size_t index1 = std::min(index0 + 1, static_cast<size_t>(sampleFrames_ - 1));
            const float frac = static_cast<float>(voice.position - static_cast<double>(index0));

            const int sampleIndex0 = static_cast<int>(index0) * channels_;
            const int sampleIndex1 = static_cast<int>(index1) * channels_;

            float sampleL0 = sampleData_[sampleIndex0];
            float sampleL1 = sampleData_[sampleIndex1];
            float sampleR0 = channels_ > 1 ? sampleData_[sampleIndex0 + 1] : sampleL0;
            float sampleR1 = channels_ > 1 ? sampleData_[sampleIndex1 + 1] : sampleL1;

            const float leftSample = sampleL0 + (sampleL1 - sampleL0) * frac;
            const float rightSample = sampleR0 + (sampleR1 - sampleR0) * frac;

            left += leftSample * voice.gain;
            right += rightSample * voice.gain;

            voice.position += voice.step;
            advanceEnvelope(voice);
        }

        left = std::clamp(left, -1.0f, 1.0f);
        right = std::clamp(right, -1.0f, 1.0f);

        if (outputChannels_ == 1) {
            output[frame] = left;
        } else {
            output[frame * outputChannels_] = left;
            output[frame * outputChannels_ + 1] = right;
            for (int channel = 2; channel < outputChannels_; ++channel) {
                output[frame * outputChannels_ + channel] = (left + right) * 0.5f;
            }
        }
    }
}

double VoiceManager::computeStepFor(int midiNote) const {
    const double semitoneOffset = static_cast<double>(midiNote - baseNote_);
    return std::pow(2.0, semitoneOffset / 12.0);
}

int VoiceManager::findVoiceFor(int midiNote) {
    for (int i = 0; i < kMaxVoices; ++i) {
        if (voices_[i].stage != Stage::Idle && voices_[i].note == midiNote) {
            return i;
        }
    }
    return -1;
}

int VoiceManager::findFreeVoice() {
    for (int i = 0; i < kMaxVoices; ++i) {
        if (voices_[i].stage == Stage::Idle) {
            return i;
        }
    }
    return -1;
}

int VoiceManager::stealVoice() {
    int target = 0;
    float minGain = std::numeric_limits<float>::max();
    for (int i = 0; i < kMaxVoices; ++i) {
        if (voices_[i].gain < minGain) {
            minGain = voices_[i].gain;
            target = i;
        }
    }
    return target;
}

void VoiceManager::beginRelease(Voice& voice) {
    if (voice.stage != Stage::Idle) {
        voice.stage = Stage::Release;
    }
}

void VoiceManager::advanceEnvelope(Voice& voice) {
    switch (voice.stage) {
    case Stage::Attack:
        voice.gain += attackIncrement_;
        if (voice.gain >= 1.0f) {
            voice.gain = 1.0f;
            voice.stage = Stage::Sustain;
        }
        break;
    case Stage::Sustain:
        if (voice.position >= static_cast<double>(sampleFrames_)) {
            voice.stage = Stage::Release;
        }
        break;
    case Stage::Release:
        voice.gain -= releaseIncrement_;
        if (voice.gain <= kMinimumGain) {
            voice.stage = Stage::Idle;
            voice.gain = 0.0f;
            voice.position = 0.0;
        }
        break;
    case Stage::Idle:
        break;
    }
}

