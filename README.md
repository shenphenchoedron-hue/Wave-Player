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
