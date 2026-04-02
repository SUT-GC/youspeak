# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This App Does

YouSpeak is a macOS speech-to-text tool: hold a hotkey (default: right Option), speak, release — the transcribed text is typed into whatever is focused. It uses DashScope's Paraformer streaming ASR with optional LLM text polishing.

## Two Implementations

There are two maintained versions:

- **Python CLI** (`main.py`) — simpler, uses dashscope SDK + pynput
- **Swift native app** (`swift/YouSpeak/`) — primary development target, native macOS menubar app

Active development is on the Swift version.

## Build & Run

### Swift (Primary)

Open `swift/YouSpeak.xcodeproj` in Xcode and run, or:

```bash
cd swift
xcodebuild -project YouSpeak.xcodeproj -scheme YouSpeak -configuration Debug build
```

To build and notarize a release DMG:

```bash
cd swift && ./release.sh
```

Requires: Xcode 15+, macOS 13+.

The app needs two permissions granted at first launch:
- **Microphone** — for audio capture
- **Accessibility** — for CGEvent keyboard injection (auto-retries every 2s until granted)

### Python CLI

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
cp .env.example .env   # then fill in DASHSCOPE_API_KEY
.venv/bin/python3 main.py
```

## Configuration

**Swift:** All settings are in the Settings window (hotkey, API keys, LLM provider). Persisted via `UserDefaults`.

**Python:** Set `DASHSCOPE_API_KEY` in `.env`. Change hotkey by editing `HOTKEY` near the top of `main.py`.

## Architecture (Swift App)

The pipeline on every hotkey press:

```
HotkeyManager (CGEvent tap)
  → SpeechController (orchestrator, @MainActor)
      → AudioRecorder (AVAudioEngine, 16 kHz PCM mono, 200ms chunks)
      → DashScopeASR (WebSocket streaming to Paraformer-realtime-v2)
      → LLMService (optional polish via Qwen or Doubao REST)
      → TextInjector (CGEvent per character, 4ms gap)
```

Key files:
- [SpeechController.swift](swift/YouSpeak/SpeechController.swift) — top-level state machine; coordinates record → ASR → polish → inject
- [DashScopeASR.swift](swift/YouSpeak/DashScopeASR.swift) — custom WebSocket JSON implementation for streaming ASR; accumulates sentences by ID
- [AudioRecorder.swift](swift/YouSpeak/AudioRecorder.swift) — AVAudioEngine tap with resampling; thread-safe buffer via `NSLock`
- [TextInjector.swift](swift/YouSpeak/TextInjector.swift) — sends CGEvent keystrokes; requires Accessibility permission
- [HotkeyManager.swift](swift/YouSpeak/HotkeyManager.swift) — global CGEvent tap; suppresses the key from reaching other apps; auto-retries if accessibility denied
- [SettingsManager.swift](swift/YouSpeak/SettingsManager.swift) — `UserDefaults` wrapper; source of truth for all runtime config
- [StatusBarController.swift](swift/YouSpeak/StatusBarController.swift) — menubar icon rendering; observes `SpeechController.$state` via Combine to update icon (idle/recording/processing)
- [AppDelegate.swift](swift/YouSpeak/AppDelegate.swift) — app entry point; wires all components together, owns the Settings window

## Concurrency Model (Swift)

- `SpeechController` is `@MainActor`; all state transitions happen on the main thread
- `AudioRecorder` uses `NSLock` to protect the PCM buffer written from an audio thread
- ASR and LLM calls are `async`/`await` tasks launched from `SpeechController`
- Guard flags (`isRecording`, task handles) prevent overlapping sessions from a fast double-tap

## DashScope ASR Protocol

The Swift ASR client speaks a custom binary-over-WebSocket protocol:
1. Send JSON `run-task` with `task_id` (UUID), `model`, `format: "pcm"`, `sample_rate: 16000`
2. Stream raw PCM binary frames as the user speaks
3. Send JSON `finish-task` when recording stops
4. Receive JSON `result-generated` events with sentence results; accumulate by `sentence_id`
5. Final text = sentences joined in order

Authentication: `Authorization: bearer <API_KEY>` header on the WebSocket upgrade.
