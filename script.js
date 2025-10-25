const noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
const midiStart = 21; // A0
const midiEnd = 108; // C8
const notes = [];

for (let midi = midiStart; midi <= midiEnd; midi++) {
  const name = noteNames[midi % 12];
  const octave = Math.floor(midi / 12) - 1;
  const fullName = `${name}${octave}`;
  const frequency = 440 * Math.pow(2, (midi - 69) / 12);
  notes.push({ midi, name: fullName, frequency, isSharp: name.includes("#") });
}

const keyboardEl = document.getElementById("keyboard");
const baseNoteSelect = document.getElementById("baseNote");
const filePicker = document.getElementById("filePicker");
const statusEl = document.getElementById("status");

let audioContext = null;
let audioBuffer = null;
let baseNote = notes.find((note) => note.name === "C4") ?? notes[Math.floor(notes.length / 2)];
const activeVoices = new Map();

function ensureContext() {
  if (!audioContext) {
    audioContext = new (window.AudioContext || window.webkitAudioContext)();
  }
  return audioContext;
}

function formatFrequency(freq) {
  return `${freq.toFixed(2)} Hz`;
}

function populateBaseSelect() {
  notes.forEach((note) => {
    const option = document.createElement("option");
    option.value = note.name;
    option.textContent = `${note.name} (${formatFrequency(note.frequency)})`;
    if (note.name === baseNote.name) {
      option.selected = true;
    }
    baseNoteSelect.append(option);
  });
}

function createKeyElement(note) {
  const button = document.createElement("button");
  button.type = "button";
  button.dataset.note = note.name;
  button.dataset.frequency = note.frequency;
  button.className = note.isSharp ? "key black" : "key white";

  const label = document.createElement("span");
  label.className = "label";
  label.textContent = note.name;
  button.append(label);

  button.addEventListener("pointerdown", (event) => {
    event.preventDefault();
    button.setPointerCapture(event.pointerId);
    playNote(note.name);
  });

  button.addEventListener("pointerup", (event) => {
    event.preventDefault();
    releaseNote(note.name);
    button.releasePointerCapture(event.pointerId);
  });

  button.addEventListener("pointerleave", () => {
    releaseNote(note.name);
  });

  button.addEventListener("lostpointercapture", () => {
    releaseNote(note.name);
  });

  return button;
}

function buildKeyboard() {
  let lastWhiteWrapper = null;

  notes.forEach((note) => {
    if (note.isSharp) {
      if (lastWhiteWrapper) {
        const key = createKeyElement(note);
        key.setAttribute("aria-label", note.name);
        lastWhiteWrapper.append(key);
      }
      return;
    }

    const wrapper = document.createElement("div");
    wrapper.className = "key-wrapper";
    const key = createKeyElement(note);
    key.setAttribute("aria-label", note.name);
    wrapper.append(key);
    keyboardEl.append(wrapper);
    lastWhiteWrapper = wrapper;
  });
}

function stopActiveVoice(noteName) {
  const voice = activeVoices.get(noteName);
  if (!voice) {
    return;
  }
  const { source, gainNode, stopTimeout } = voice;
  if (stopTimeout) {
    clearTimeout(stopTimeout);
  }
  const ctx = ensureContext();
  const now = ctx.currentTime;
  const releaseTime = 0.12;
  gainNode.gain.cancelScheduledValues(now);
  gainNode.gain.setValueAtTime(gainNode.gain.value, now);
  gainNode.gain.linearRampToValueAtTime(0, now + releaseTime);
  source.stop(now + releaseTime + 0.02);
  activeVoices.delete(noteName);
  const keyButton = keyboardEl.querySelector(`[data-note="${noteName}"]`);
  if (keyButton) {
    keyButton.classList.remove("active");
  }
}

function playNote(noteName) {
  if (!audioBuffer) {
    statusEl.textContent = "Indlæs en WAV-fil først.";
    return;
  }

  const ctx = ensureContext();
  if (ctx.state === "suspended") {
    ctx.resume();
  }

  const note = notes.find((entry) => entry.name === noteName);
  if (!note) {
    return;
  }

  stopActiveVoice(noteName);

  const source = ctx.createBufferSource();
  source.buffer = audioBuffer;

  const playbackRate = note.frequency / baseNote.frequency;
  source.playbackRate.value = playbackRate;

  const gainNode = ctx.createGain();
  const now = ctx.currentTime;
  const attackTime = 0.02;

  gainNode.gain.setValueAtTime(0, now);
  gainNode.gain.linearRampToValueAtTime(1, now + attackTime);

  source.connect(gainNode).connect(ctx.destination);

  const adjustedDuration = audioBuffer.duration / playbackRate;
  const stopTimeout = setTimeout(() => stopActiveVoice(noteName), adjustedDuration * 1000);

  source.start(now);

  activeVoices.set(noteName, { source, gainNode, stopTimeout });

  const keyButton = keyboardEl.querySelector(`[data-note="${noteName}"]`);
  if (keyButton) {
    keyButton.classList.add("active");
  }
}

function releaseNote(noteName) {
  stopActiveVoice(noteName);
}

async function loadFile(file) {
  const ctx = ensureContext();
  if (ctx.state === "suspended") {
    await ctx.resume();
  }

  statusEl.textContent = "Indlæser...";
  try {
    const arrayBuffer = await file.arrayBuffer();
    const decoded = await ctx.decodeAudioData(arrayBuffer);
    audioBuffer = decoded;
    statusEl.textContent = `Indlæst: ${file.name} (${decoded.duration.toFixed(2)} sek.)`;
  } catch (error) {
    console.error(error);
    statusEl.textContent = "Kunne ikke indlæse filen.";
  }
}

filePicker.addEventListener("change", async (event) => {
  const file = event.target.files?.[0];
  if (file) {
    await loadFile(file);
  }
});

baseNoteSelect.addEventListener("change", (event) => {
  const selectedName = event.target.value;
  const note = notes.find((entry) => entry.name === selectedName);
  if (note) {
    baseNote = note;
  }
});

populateBaseSelect();
buildKeyboard();
statusEl.textContent = "Vælg en WAV-fil for at begynde.";
