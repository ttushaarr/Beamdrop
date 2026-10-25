# BeamDrop: AirDrop & KDE Connect for macOS and Android

> **Fast, secure, local Wi-Fi file sharing & bidirectional device integration.**  
> Seamless zero-click file transfers, live clipboard synchronization, remote trackpad gestures, media remote, presentation clicker, and system automations between MacBook and Android.  
> **100% Open Source • 100% Local Wi-Fi • Zero Cloud Servers • Zero Telemetry.**

🌐 **Live Website & Docs**: [`website/index.html`](website/index.html) or deploy with GitHub Pages via `/docs`.  
📜 **License**: [MIT License](LICENSE).

---

## 1. Features at a Glance

| Feature | Description | macOS | Android |
| :--- | :--- | :---: | :---: |
| ⚡ **Zero-Click File Drops** | Photos, videos, and docs auto-route into `Pictures/`, `Movies/`, and `Download/` with instant gallery indexing. | ✅ Sender | ✅ Receiver |
| 📋 **Live Clipboard Sync** | Copy on Mac, paste on Android. Copy on Android, paste on Mac. Sub-10ms latency over local SSE. | ✅ Bi-dir | ✅ Bi-dir |
| 🖱️ **Remote Trackpad & Keys** | Use your Android device as a wireless Mac trackpad (drag, tap-to-click, right-click, scroll strip, typing). | ✅ Server | ✅ Client |
| 🎵 **Media Remote (MPRIS)** | Control Spotify, Apple Music, and Mac system audio volume remotely from your device. | ✅ Server | ✅ Client |
| 🖥️ **Presentation Clicker** | Giant Next/Prev slide buttons, presentation timer, F5 full-screen start, and B blackout key. | ✅ Server | ✅ Client |
| ⚙️ **One-Tap System Commands** | Lock screen, sleep, take desktop screenshot, mute, empty trash, launch Terminal, and open URLs. | ✅ Server | ✅ Client |
| 🔔 **Find My Device Ringing** | Ring Android device with max volume alarm + vibration from Mac, or ring Mac loudly from Android. | ✅ Bi-dir | ✅ Bi-dir |
| 🔋 **Bidirectional Battery** | Real-time battery percentage and charging indicator (⚡) visible on both devices. | ✅ Bi-dir | ✅ Bi-dir |
| 📲 **Notification Mirroring** | Mirror incoming Android notifications to macOS Notification Center. | ✅ Display | ✅ Streamer |

---

### The Transfer Pipeline

```
[MacBook (macOS)] ──(Local Wi-Fi / Direct TCP)──> [Android Device (Phone / Tablet)]
        │                                                     │
   Drag & Drop                                       Background Service
   or File Picker                                             │
        │                                            Scoped Storage Router
   SHA-256 Stream                                             │
                                           ┌──────────────────┼──────────────────┐
                                           ▼                  ▼                  ▼
                                       Pictures/           Movies/           Download/
                                    LaptopTransfer/    LaptopTransfer/    LaptopTransfer/
                                           │                  │                  │
                                     Google Photos/        Gallery         Files / Docs
                                        Gallery          Auto-Indexed
```

### The Workflow:
1. **Initial Pairing (One-Time Only)**:
   - Launch BeamDrop on both devices.
   - Enter the 6-digit PIN code displayed on the Android device into the Mac app (or scan the QR payload).
   - Trust credentials and cryptographic auth tokens are established and persisted.
2. **Transferring Files**:
   - On Mac: Drag and drop any file or click **Select File**.
   - With **"Send automatically on select"** checked, transfer starts immediately! (Or click **Send Now**).
   - Transfer streams directly over local Wi-Fi with real-time speed (MB/s), ETA countdown, and progress bar.
   - **On the Android device: Zero manual steps required.** The device saves the file automatically into the appropriate storage folder with MediaStore registration.

---

## 2. Automatic Android Storage Routing (MediaStore Integration)

All incoming files are routed dynamically based on MIME type and extension using modern Scoped Storage APIs:

| File Type | Extensions | Device Storage Path | Gallery Integration |
|---|---|---|---|
| **Photos & Images** | `.jpg`, `.jpeg`, `.png`, `.webp`, `.heic`, `.gif`, `.avif`, `.bmp`, `.tiff` | `Pictures/LaptopTransfer/` | **Immediate Gallery / Google Photos indexing** via `MediaStore.Images` (`IS_PENDING = 0`) |
| **Videos** | `.mp4`, `.mkv`, `.mov`, `.webm`, `.avi`, `.3gp`, `.m4v` | `Movies/LaptopTransfer/` | **Immediate Gallery video indexing** via `MediaStore.Video` |
| **Documents & Archives** | `.pdf`, `.zip`, `.tar`, `.gz`, `.7z`, `.docx`, `.xlsx`, code, text | `Download/LaptopTransfer/` | Standard `Download/` folder via `MediaStore.Downloads` |

### Duplicate File Protection
BeamDrop **never silently overwrites** existing files. If `photo.jpg` already exists in `Pictures/LaptopTransfer/`, the incoming file is automatically saved as `photo (1).jpg`, `photo (2).jpg`, etc., preserving the original file extension and integrity.

---

## 3. Security & Privacy Architecture

- **Local Network Only**: Transfers occur over direct TCP sockets on your local Wi-Fi network. No telemetry, analytics, third-party relays, or cloud servers.
- **Mutual Device Trust**: Unpaired devices receive `HTTP 401 Unauthorized` and are instantly rejected.
- **Cryptographic PIN Authentication**: One-time 6-digit pairing PIN generates a persistent SHA-256 Bearer Token exchanged over HTTP and verified on every transfer chunk.
- **SHA-256 Bit-for-Bit Integrity**: Mac calculates the SHA-256 hash before sending; Android verifies the checksum during transfer to ensure 100% uncorrupted delivery.

---

## 4. Architecture & Directory Structure

```
beamdrop/
├── macos/                     # Native macOS Sender (Swift 5.9, SwiftUI)
│   ├── Sources/BeamDrop/
│   │   ├── App/               # Entrypoint & AppDelegate
│   │   ├── Models/            # TransferItem, PairedDevice, KdeModels
│   │   ├── Services/          # TransferClient, ClipboardSync, Discovery, KDE Connect
│   │   └── Views/             # SwiftUI DropZone, KDE Connect, Progress, History
│   └── Resources/             # App icons & Entitlements
├── android/                   # Native Android Receiver (Kotlin, Jetpack Compose)
│   └── app/src/main/java/com/beamdrop/receiver/
│       ├── model/             # TransferRecord, KdeConnectModels, PairedDevice
│       ├── security/          # PairingManager & Keystore token storage
│       ├── server/            # Embedded lightweight HTTP server (:8765)
│       ├── service/           # FileReceiverForegroundService & NotificationListener
│       ├── storage/           # Scoped Storage MediaStore Router
│       └── ui/                # Jetpack Compose Screens (Trackpad, Media, Commands)
├── website/                   # Open-source landing page
├── docs/                      # GitHub Pages static documentation
└── scripts/                   # Automated build scripts
```

---

## 5. Building & Running the Applications

### 5.1 macOS Sender Application

The pre-built native application bundle is located in `dist/`:
```bash
open dist/BeamDrop.app
```

#### Rebuilding the macOS App from source:
```bash
chmod +x scripts/build_macos_app.sh
bash scripts/build_macos_app.sh
```

---

### 5.2 Android Receiver Application

#### Building the APK with Gradle:
1. Ensure `ANDROID_HOME` or your Android SDK path is exported:
   ```bash
   export ANDROID_HOME="$HOME/Library/Android/sdk"
   ```
2. Navigate to the android project directory and build the debug APK:
   ```bash
   cd android && ./gradlew assembleDebug
   ```
3. The APK will be generated at:
   ```
   android/app/build/outputs/apk/debug/app-debug.apk
   ```

#### Installing onto your Android device via USB or Wireless ADB:
```bash
adb install -r dist/BeamDrop-Receiver.apk
```

#### Opening in Android Studio:
Alternatively, launch Android Studio, click **Open**, and choose the `android` folder in this repository.

---

## 6. Configuring Background Receiving on Android

Android actively throttles background execution to conserve battery. To ensure BeamDrop stays responsive when the screen turns off or while using other apps:

1. **Disable Battery Optimization**:
   - In BeamDrop on Android, go to the **Settings** tab.
   - Tap **"Disable Battery Optimization"** and select **Allow** (`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`).
2. **App Battery Settings**:
   - Open device **Settings → Apps → BeamDrop → Battery**.
   - Select **Unrestricted** (prevents Android from putting the app to sleep).
3. **Lock App in Recent Apps Screen**:
   - Swipe up and hold to open Recent Apps.
   - Tap the BeamDrop app icon at the top of its window card and tap **Lock**. This prevents the OS from clearing it during RAM memory pressure.
4. **Foreground Service Ongoing Notification**:
   - BeamDrop automatically runs an ongoing notification ("BeamDrop Active"). This signals the Android system kernel to keep the background process alive.

---

## 7. Troubleshooting Guide

- **Mac cannot discover the Android device automatically:**
  - Some Wi-Fi routers disable mDNS / multicast between clients (AP Isolation).
  - Open BeamDrop on your Android device, look at the IP address shown on the dashboard (e.g. `192.168.1.45`), go to **Settings** on your Mac, enter the IP, and click **Scan / Ping**.
- **Transfer fails or times out:**
  - Ensure both devices are connected to the same Wi-Fi network (or MacBook is connected to Android Wi-Fi hotspot).
  - Verify port `8765` is not blocked by local macOS firewall (`System Settings → Network → Firewall`).
- **Images don't appear in Gallery immediately:**
  - BeamDrop sets `IS_PENDING = 0` and calls `MediaScannerConnection.scanFile`. Some third-party gallery apps cache thumbnails; Google Photos and native galleries will index immediately. Pull down to refresh if needed.
- **Device stops receiving when screen turns off:**
  - Verify battery optimization is set to **Unrestricted** under `Settings → Apps → BeamDrop → Battery` as described in Section 6.
