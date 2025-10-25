# Wave Keyboard (macOS)

macOS-app bygget i C++/Objective-C++ der viser et vindue med et 88-tangenters klaver (A0–C8). En "Load Sample"-knap åbner en filvælger, og de valgte WAV-samples kan spilles på valgfri tangenter med korrekt pitch-shift (uden time-stretching). For at undgå kliklyde anvendes korte attack/release fades.

## Krav

- macOS med Xcode Command Line Tools
- CMake 3.20 eller nyere
- Clang med C++17 og Objective-C++ support

## Kompilering

```bash
cmake -B build -S .
cmake --build build
```

CMake producerer et `WaveKeyboard.app` bundle i `build/`. Appen kan åbnes direkte i Finder eller køres fra terminalen:

```bash
open build/WaveKeyboard.app
```

## Brug

1. Start appen og klik på **Load Sample** for at vælge en WAV-fil.
2. Klik på tangenterne nederst i vinduet for at afspille noterne. Pitch justeres automatisk på tværs af hele klaviaturet.
3. Der anvendes bløde fades i starten og slutningen af hver note for at forhindre kliklyde.

## Projektstruktur

- `src/main.mm` – macOS GUI (Cocoa) med vindue, filvælger og klavertegning.
- `src/SamplePlayer.mm` & `include/SamplePlayer.h` – lydmotor baseret på `AVAudioEngine` og `AVAudioUnitTimePitch` til pitch-shifting uden tempoændring.
- `CMakeLists.txt` – bygger et `MACOSX_BUNDLE` og linker mod Cocoa/AVFoundation.
