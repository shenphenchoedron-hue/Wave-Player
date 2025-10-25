#include "VoiceManager.h"

#include <SDL.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

constexpr int kFirstMidiNote = 21;  // A0
constexpr int kLastMidiNote = 108;  // C8
constexpr int kTotalKeys = kLastMidiNote - kFirstMidiNote + 1;

struct PianoKey {
    SDL_Rect bounds{};
    bool isBlack = false;
    int midiNote = 0;
    bool pressed = false;
};

bool isBlackKey(int midiNote) {
    const int mod = midiNote % 12;
    return mod == 1 || mod == 3 || mod == 6 || mod == 8 || mod == 10;
}

std::string midiNoteName(int midiNote) {
    static const std::array<const char*, 12> names = {
        "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"};
    const int mod = ((midiNote % 12) + 12) % 12;
    const int octave = midiNote / 12 - 1;
    return std::string(names[mod]) + std::to_string(octave);
}

std::optional<int> findKeyAtPosition(int x,
                                     int y,
                                     const std::array<PianoKey, kTotalKeys>& keys,
                                     const std::vector<int>& blackIndices,
                                     const std::vector<int>& whiteIndices) {
    SDL_Point point{x, y};
    for (int index : blackIndices) {
        if (SDL_PointInRect(&point, &keys[index].bounds)) {
            return index;
        }
    }
    for (int index : whiteIndices) {
        if (SDL_PointInRect(&point, &keys[index].bounds)) {
            return index;
        }
    }
    return std::nullopt;
}

void renderKeyboard(SDL_Renderer* renderer,
                    const std::array<PianoKey, kTotalKeys>& keys,
                    const std::vector<int>& whiteIndices,
                    const std::vector<int>& blackIndices,
                    int baseMidiNote) {
    for (int index : whiteIndices) {
        const auto& key = keys[index];
        const bool isBase = key.midiNote == baseMidiNote;
        const SDL_Color fill = key.pressed ? SDL_Color{220, 220, 255, 255}
                                           : isBase        ? SDL_Color{220, 240, 255, 255}
                                                           : SDL_Color{245, 245, 245, 255};
        SDL_SetRenderDrawColor(renderer, fill.r, fill.g, fill.b, fill.a);
        SDL_RenderFillRect(renderer, &key.bounds);
        SDL_SetRenderDrawColor(renderer, 40, 40, 40, 255);
        SDL_RenderDrawRect(renderer, &key.bounds);
    }

    for (int index : blackIndices) {
        const auto& key = keys[index];
        const bool isBase = key.midiNote == baseMidiNote;
        SDL_Color fill = key.pressed ? SDL_Color{80, 80, 140, 255}
                                     : isBase        ? SDL_Color{40, 40, 120, 255}
                                                    : SDL_Color{25, 25, 25, 255};
        SDL_SetRenderDrawColor(renderer, fill.r, fill.g, fill.b, fill.a);
        SDL_RenderFillRect(renderer, &key.bounds);
    }
}

std::vector<float> loadSample(const std::string& path,
                              int& sampleRate,
                              int& channels,
                              int desiredChannels) {
    SDL_AudioSpec wavSpec;
    Uint8* wavBuffer = nullptr;
    Uint32 wavLength = 0;

    if (!SDL_LoadWAV(path.c_str(), &wavSpec, &wavBuffer, &wavLength)) {
        throw std::runtime_error(std::string("Kunne ikke loade WAV fil: ") + SDL_GetError());
    }

    SDL_AudioCVT cvt;
    if (SDL_BuildAudioCVT(&cvt,
                          wavSpec.format,
                          wavSpec.channels,
                          wavSpec.freq,
                          AUDIO_F32,
                          desiredChannels,
                          wavSpec.freq) < 0) {
        SDL_FreeWAV(wavBuffer);
        throw std::runtime_error(std::string("Kunne ikke konvertere lydformat: ") + SDL_GetError());
    }

    cvt.len = static_cast<int>(wavLength);
    cvt.buf = static_cast<Uint8*>(SDL_malloc(cvt.len * cvt.len_mult));
    if (!cvt.buf) {
        SDL_FreeWAV(wavBuffer);
        throw std::runtime_error("Ikke hukommelse nok til lydkonvertering");
    }

    std::copy(wavBuffer, wavBuffer + wavLength, cvt.buf);
    if (SDL_ConvertAudio(&cvt) < 0) {
        SDL_free(cvt.buf);
        SDL_FreeWAV(wavBuffer);
        throw std::runtime_error(std::string("Fejl under lydkonvertering: ") + SDL_GetError());
    }

    SDL_FreeWAV(wavBuffer);

    const size_t sampleCount = static_cast<size_t>(cvt.len_cvt) / sizeof(float);
    std::vector<float> data(sampleCount);
    std::memcpy(data.data(), cvt.buf, cvt.len_cvt);
    SDL_free(cvt.buf);

    sampleRate = wavSpec.freq;
    channels = desiredChannels;

    if (data.empty()) {
        throw std::runtime_error("WAV filen indeholder ingen samples");
    }

    return data;
}

void audioCallback(void* userdata, Uint8* stream, int len) {
    auto* manager = static_cast<VoiceManager*>(userdata);
    float* output = reinterpret_cast<float*>(stream);
    const int frameCount = len / (sizeof(float) * manager->outputChannels());
    manager->mix(output, frameCount);
}

} // namespace

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Brug: " << argv[0] << " <sti til wav> [basis midi note (21-108)]\n";
        return 1;
    }

    const std::string filePath = argv[1];
    int baseNote = 60;
    if (argc >= 3) {
        try {
            baseNote = std::clamp(std::stoi(argv[2]), kFirstMidiNote, kLastMidiNote);
        } catch (const std::exception&) {
            std::cerr << "Ugyldig basis note, bruger standarden C4 (60)." << std::endl;
            baseNote = 60;
        }
    }

    if (SDL_Init(SDL_INIT_AUDIO | SDL_INIT_VIDEO) < 0) {
        std::cerr << "Kunne ikke initialisere SDL: " << SDL_GetError() << "\n";
        return 1;
    }

    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "1");

    const int desiredChannels = 2;
    int sampleRate = 0;
    int channels = 0;
    std::vector<float> sampleData;

    try {
        sampleData = loadSample(filePath, sampleRate, channels, desiredChannels);
    } catch (const std::exception& e) {
        std::cerr << e.what() << "\n";
        SDL_Quit();
        return 1;
    }

    VoiceManager voiceManager(sampleData, sampleRate, channels, desiredChannels, baseNote);

    SDL_AudioSpec desired{};
    desired.freq = sampleRate;
    desired.format = AUDIO_F32;
    desired.channels = desiredChannels;
    desired.samples = 1024;
    desired.callback = audioCallback;
    desired.userdata = &voiceManager;

    SDL_AudioSpec obtained{};
    SDL_AudioDeviceID device = SDL_OpenAudioDevice(nullptr, 0, &desired, &obtained, 0);
    if (!device) {
        std::cerr << "Kunne ikke åbne lyd enhed: " << SDL_GetError() << "\n";
        SDL_Quit();
        return 1;
    }

    if (obtained.format != AUDIO_F32) {
        std::cerr << "Kunne ikke få 32-bit float output fra lyd enheden" << std::endl;
        SDL_CloseAudioDevice(device);
        SDL_Quit();
        return 1;
    }

    const int outputChannels = obtained.channels;
    if (outputChannels != desiredChannels) {
        std::cerr << "Kunne ikke få ønsket kanal antal fra lyd enheden" << std::endl;
        SDL_CloseAudioDevice(device);
        SDL_Quit();
        return 1;
    }

    SDL_PauseAudioDevice(device, 0);

    const int whiteKeyWidth = 26;
    const int whiteKeyHeight = 220;
    const int blackKeyWidth = 18;
    const int blackKeyHeight = 140;
    const int margin = 24;

    const int whiteKeyCount = 52;
    const int width = whiteKeyCount * whiteKeyWidth + margin * 2;
    const int height = whiteKeyHeight + margin * 2;

    SDL_Window* window = SDL_CreateWindow("Wave Player",
                                          SDL_WINDOWPOS_CENTERED,
                                          SDL_WINDOWPOS_CENTERED,
                                          width,
                                          height,
                                          SDL_WINDOW_SHOWN);
    if (!window) {
        std::cerr << "Kunne ikke oprette vindue: " << SDL_GetError() << "\n";
        SDL_CloseAudioDevice(device);
        SDL_Quit();
        return 1;
    }

    SDL_Renderer* renderer =
        SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!renderer) {
        std::cerr << "Kunne ikke oprette renderer: " << SDL_GetError() << "\n";
        SDL_DestroyWindow(window);
        SDL_CloseAudioDevice(device);
        SDL_Quit();
        return 1;
    }

    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND);

    std::array<PianoKey, kTotalKeys> keys{};
    std::vector<int> whiteIndices;
    std::vector<int> blackIndices;
    whiteIndices.reserve(52);
    blackIndices.reserve(36);

    std::array<int, 128> whiteKeyPositions{};
    whiteKeyPositions.fill(-1);

    int whiteIndex = 0;
    const int keyboardTop = margin;

    for (int i = 0; i < kTotalKeys; ++i) {
        const int midiNote = kFirstMidiNote + i;
        if (!isBlackKey(midiNote)) {
            const int x = margin + whiteIndex * whiteKeyWidth;
            keys[i].bounds = SDL_Rect{x, keyboardTop, whiteKeyWidth, whiteKeyHeight};
            keys[i].isBlack = false;
            keys[i].midiNote = midiNote;
            whiteIndices.push_back(i);
            whiteKeyPositions[midiNote] = x;
            ++whiteIndex;
        }
    }

    for (int i = 0; i < kTotalKeys; ++i) {
        const int midiNote = kFirstMidiNote + i;
        if (isBlackKey(midiNote)) {
            int prevNote = midiNote - 1;
            while (prevNote >= kFirstMidiNote && isBlackKey(prevNote)) {
                --prevNote;
            }
            int nextNote = midiNote + 1;
            while (nextNote <= kLastMidiNote && isBlackKey(nextNote)) {
                ++nextNote;
            }

            const int prevX = whiteKeyPositions[prevNote];
            if (prevX < 0) {
                continue;
            }
            int nextX = -1;
            if (nextNote <= kLastMidiNote) {
                nextX = whiteKeyPositions[nextNote];
            }
            if (nextX < 0) {
                nextX = prevX + whiteKeyWidth;
            }

            const int prevCenter = prevX + whiteKeyWidth / 2;
            const int nextCenter = nextX + whiteKeyWidth / 2;
            const int center = (prevCenter + nextCenter) / 2;
            const int x = center - blackKeyWidth / 2;

            keys[i].bounds = SDL_Rect{x, keyboardTop, blackKeyWidth, blackKeyHeight};
            keys[i].isBlack = true;
            keys[i].midiNote = midiNote;
            blackIndices.push_back(i);
        }
    }

    const std::string title = "Wave Player - " + midiNoteName(baseNote) +
                              " (" + std::to_string(sampleRate) + " Hz)";
    SDL_SetWindowTitle(window, title.c_str());

    bool running = true;
    bool mouseDown = false;
    std::optional<int> activeKeyIndex;

    while (running) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            switch (event.type) {
            case SDL_QUIT:
                running = false;
                break;
            case SDL_KEYDOWN:
                if (event.key.keysym.sym == SDLK_ESCAPE) {
                    running = false;
                } else if (event.key.keysym.sym == SDLK_SPACE && activeKeyIndex) {
                    voiceManager.noteOff(keys[*activeKeyIndex].midiNote);
                    keys[*activeKeyIndex].pressed = false;
                    activeKeyIndex.reset();
                } else if (event.key.keysym.sym == SDLK_BACKSPACE) {
                    voiceManager.stopAll();
                    for (auto& key : keys) {
                        key.pressed = false;
                    }
                    activeKeyIndex.reset();
                }
                break;
            case SDL_MOUSEBUTTONDOWN:
                if (event.button.button == SDL_BUTTON_LEFT) {
                    mouseDown = true;
                    const auto keyIndex =
                        findKeyAtPosition(event.button.x, event.button.y, keys, blackIndices, whiteIndices);
                    if (keyIndex) {
                        activeKeyIndex = keyIndex;
                        auto& key = keys[*keyIndex];
                        key.pressed = true;
                        voiceManager.noteOn(key.midiNote);
                    }
                }
                break;
            case SDL_MOUSEBUTTONUP:
                if (event.button.button == SDL_BUTTON_LEFT) {
                    mouseDown = false;
                    if (activeKeyIndex) {
                        auto& key = keys[*activeKeyIndex];
                        key.pressed = false;
                        voiceManager.noteOff(key.midiNote);
                        activeKeyIndex.reset();
                    }
                }
                break;
            case SDL_WINDOWEVENT:
                if (event.window.event == SDL_WINDOWEVENT_LEAVE && mouseDown) {
                    mouseDown = false;
                    if (activeKeyIndex) {
                        auto& key = keys[*activeKeyIndex];
                        key.pressed = false;
                        voiceManager.noteOff(key.midiNote);
                        activeKeyIndex.reset();
                    }
                }
                break;
            case SDL_MOUSEMOTION:
                if (mouseDown) {
                    const auto keyIndex =
                        findKeyAtPosition(event.motion.x, event.motion.y, keys, blackIndices, whiteIndices);
                    if (keyIndex && (!activeKeyIndex || *keyIndex != *activeKeyIndex)) {
                        if (activeKeyIndex) {
                            auto& previous = keys[*activeKeyIndex];
                            previous.pressed = false;
                            voiceManager.noteOff(previous.midiNote);
                        }
                        activeKeyIndex = keyIndex;
                        auto& key = keys[*keyIndex];
                        key.pressed = true;
                        voiceManager.noteOn(key.midiNote);
                    }
                }
                break;
            default:
                break;
            }
        }

        SDL_SetRenderDrawColor(renderer, 15, 15, 25, 255);
        SDL_RenderClear(renderer);

        renderKeyboard(renderer, keys, whiteIndices, blackIndices, baseNote);

        SDL_RenderPresent(renderer);
        SDL_Delay(16);
    }

    SDL_PauseAudioDevice(device, 1);
    SDL_CloseAudioDevice(device);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();

    return 0;
}

