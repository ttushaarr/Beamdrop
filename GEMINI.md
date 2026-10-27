# BeamDrop Project Memory & Context Guidelines

## 1. Project Overview
- **Name**: BeamDrop
- **Repository**: [https://github.com/ttushaarr/beamdrop](https://github.com/ttushaarr/beamdrop)
- **Website**: [https://ttushaarr.github.io/beamdrop/](https://ttushaarr.github.io/beamdrop/) (served from `/docs`)
- **License**: MIT License
- **Purpose**: High-speed, local Wi-Fi AirDrop and KDE Connect suite between macOS (Apple Silicon / Sonoma & Sequoia) and Android (phones and tablets, Android 9.0+ to Android 15+).
- **Core Philosophy**: 100% offline, zero cloud servers, zero telemetry, zero confirmation prompts.

## 2. Core Feature Matrix
1. **Zero-Click File Drops**:
   - Automated Scoped Storage routing:
     - Photos -> `Pictures/LaptopTransfer/` with immediate Gallery / Google Photos indexing (`IS_PENDING = 0`).
     - Videos -> `Movies/LaptopTransfer/` with video player indexing.
     - Documents & Archives -> `Download/LaptopTransfer/`.
   - Never overwrites files; appends ` (1)`, ` (2)` automatically.
2. **Live Bidirectional Clipboard Sync**:
   - Sub-10ms streaming via Server-Sent Events (SSE).
   - Copy on Mac -> auto-pastes on Android. Copy on Android -> auto-pastes on Mac.
3. **KDE Connect Suite**:
   - **Remote Trackpad & Keyboard**: Cursor motion, left/right/double click, vertical scroll strip, soft text entry, modifier keys (`Esc`, `Tab`, `Return`, `Space`, `Backspace`).
   - **Media Player Remote**: Play/Pause, Next/Previous track, system volume slider (0-100%), and mute toggle (Spotify, Apple Music, System Events).
   - **Presentation Clicker**: Next/Prev slide buttons, presentation timer, `F5` fullscreen start, `B` blackout key, `Esc` exit.
   - **One-Tap System Commands**: Lock screen, Sleep, Screenshot (saved to `~/Desktop`), Mute, Empty Trash, Launch Terminal, Open URL.
   - **Find My Device**: Ring Android at maximum volume (`USAGE_ALARM`) with vibration even if muted, or Ring Mac loudly with ping & speech locator.
   - **Real-Time Battery Status**: Bidirectional battery percentage and charging indicator (⚡).
   - **Notification Mirroring**: Android notifications streamed to macOS Notification Center.

## 3. Universal Ad & Promotion Context
- **Target Audience**: Anyone using a MacBook + Android device (phone or tablet) who misses AirDrop.
- **Brand Mentions**: Universal references only (do NOT restrict to specific brands like "Moto"). Reference "Android device", "phone", or "tablet".
- **350-Character Description**:
  > BeamDrop connects macOS and Android over local Wi-Fi with zero cloud servers. Enjoy instant file drops with automatic gallery sorting, live bidirectional clipboard sync, remote trackpad and keyboard controls, media playback, presentation clicker, and system automations. 100% private, open-source, and offline with zero manual confirmation prompts.

## 4. Key Paths
- **macOS App**: `/Applications/BeamDrop.app` and `~/Desktop/BeamDrop.app`
- **Android APK**: `dist/BeamDrop-Receiver.apk` and `~/Desktop/BeamDrop-Receiver.apk`
- **Mac Release ZIP**: `dist/BeamDrop-Mac.zip` and `~/Desktop/BeamDrop-Mac.zip`
- **Landing Page**: `website/index.html` and `docs/index.html`
