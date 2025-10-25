# Wave Keyboard (macOS)

macOS-app bygget i C++/Objective-C++ der viser et vindue med et 88-tangenters klaver (A0–C8). En "Load Sample"-knap åbner en filvælger, og de valgte WAV-samples kan spilles på valgfri tangenter med korrekt pitch-shift (uden time-stretching). For at undgå kliklyde anvendes korte attack/release fades.

## Krav

- macOS med Xcode Command Line Tools
- CMake 3.20 eller nyere
- Clang med C++17 og Objective-C++ support
# Wave Player

Et lille SDL2-baseret værktøj der kan loade en WAV-fil og afspille den via et virtuelt klaver med 88 tangenter. Programmet bruger sample-rate resampling for at ramme de korrekte toner uden time-stretching og har bløde attack/release overgange for at undgå kliklyde.

## Krav

- CMake 3.16 eller nyere
- En C++17-kompatibel compiler
- SDL2 (udviklingsbiblioteker)

På Ubuntu/Debian kan SDL2 installeres med:

```bash
sudo apt-get install libsdl2-dev
```

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

> **Bemærk:** På ikke-macOS platforme konfigurerer CMake stadig projektet, men der oprettes kun et stub-target, da Cocoa- og AVFoundation-frameworks kræves for selve applikationen.
## Kørsel

```bash
./build/wave_player <sti til wav-fil> [basis-midi-note]
```

- `basis-midi-note` er valgfri og angiver hvilken tangent der svarer til den samplede tone (standard er 60, dvs. C4).
- Klik på tangenterne med musen for at trigge noter. Du kan trække henover tangenterne for glissando. `Esc` lukker appen, `Backspace` slukker alle toner.

## Funktioner

- Afspiller WAV-samples (mono eller stereo) med korrekt pitch-kontrol på tværs af alle 88 tangenter.
- Envelope (attack/release) skaber en lille crossfade, der fjerner kliklyde ved note start/stop.
- Visuel gengivelse af hele klaviaturet med markering af aktiv basis-tone.
