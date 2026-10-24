# BeamDrop Local Transfer Protocol Specification (v1.0)

## Overview
BeamDrop is a zero-configuration, secure, local-network file transfer protocol engineered specifically for transferring files from macOS (Sender) to Android (Receiver, e.g. Motorola Moto Pad 60 Pro) over direct Wi-Fi.

- **Transport**: HTTP/1.1 or HTTP/2 over TCP with streaming chunked transfer.
- **Port**: Default `8765` (configurable).
- **Service Discovery**: mDNS / DNS-SD (Bonjour / Android NSD).
  - Service Type: `_beamdrop._tcp.`
  - Domain: `local.`
- **Security**: Local network isolation, out-of-band PIN/QR code pairing, HMAC/Bearer Auth Token, and streaming SHA-256 integrity verification.

---

## 1. Network Discovery

### 1.1 Android Receiver Advertisement
Android publishes a DNS-SD service:
- Service Name: `BeamDrop-<DeviceName>` (e.g. `BeamDrop-Moto-Pad-60-Pro`)
- Service Type: `_beamdrop._tcp.`
- Port: `8765`
- TXT Records:
  - `id`: `<unique-receiver-uuid>`
  - `name`: `Moto Pad 60 Pro`
  - `version`: `1`
  - `platform`: `android`

### 1.2 macOS Sender Discovery
macOS uses `NWBrowser` from Apple's `Network.framework` to browse for `_beamdrop._tcp.` services. Upon finding a service, it resolves the IP address and port and performs a lightweight `/api/v1/ping` health check.

---

## 2. Pairing & Trust Establishment

Pairing occurs once per Mac-tablet pair. Once paired, all subsequent transfers happen with **zero user confirmation** on the tablet.

### 2.1 QR Code / PIN Generation (Android)
Android generates:
1. A 6-digit numeric pairing PIN: `123456` (expires in 10 minutes or upon successful pairing).
2. A QR Code encoding JSON:
```json
{
  "version": 1,
  "deviceId": "moto-pad-60-pro-uuid",
  "deviceName": "Moto Pad 60 Pro",
  "ip": "192.168.1.45",
  "port": 8765,
  "pairingSecret": "123456"
}
```

### 2.2 Pairing Handshake Request (macOS -> Android)
`POST /api/v1/pair`

**Headers:**
- `Content-Type`: `application/json`

**Body:**
```json
{
  "senderId": "macbook-pro-uuid",
  "senderName": "MacBook Pro",
  "pairingSecret": "123456",
  "clientAuthToken": "32-byte-hex-string"
}
```

### 2.3 Pairing Handshake Response (Android -> macOS)
- If `pairingSecret` matches:
  - Status: `200 OK`
  - Body:
    ```json
    {
      "status": "PAIRED",
      "receiverId": "moto-pad-60-pro-uuid",
      "receiverName": "Moto Pad 60 Pro",
      "serverAuthToken": "32-byte-hex-string"
    }
    ```
- If `pairingSecret` does not match:
  - Status: `403 Forbidden`
  - Body: `{ "error": "Invalid pairing secret" }`

Both devices securely persist each other's ID and tokens.

---

## 3. File Transfer Pipeline

### 3.1 Step 1: Transfer Initialization
`POST /api/v1/transfer/init`

**Headers:**
- `Authorization`: `Bearer <serverAuthToken>`
- `X-BeamDrop-Sender-Id`: `<macbook-pro-uuid>`
- `Content-Type`: `application/json`

**Body:**
```json
{
  "transferId": "transfer-uuid-1234",
  "fileName": "landscape.jpg",
  "fileSize": 12459800,
  "mimeType": "image/jpeg",
  "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "timestamp": 1729763000
}
```

**Android Processing:**
1. Validates `Authorization` against paired devices store.
   - If missing or invalid: Returns `401 Unauthorized`.
2. Validates available storage space.
   - If disk space is lower than `fileSize + 50MB`: Returns `507 Insufficient Storage`.
3. Resolves target storage location according to file type:
   - **Images** (`.jpg`, `.jpeg`, `.png`, `.webp`, `.heic`, `.gif`, `.avif`, `.bmp`, `.tiff`):
     - MediaStore: `MediaStore.Images.Media.EXTERNAL_CONTENT_URI`
     - Relative Path: `Pictures/LaptopTransfer/`
   - **Videos** (`.mp4`, `.mkv`, `.mov`, `.webm`, `.avi`, `.3gp`):
     - MediaStore: `MediaStore.Video.Media.EXTERNAL_CONTENT_URI`
     - Relative Path: `Movies/LaptopTransfer/`
   - **All Other Files** (`.pdf`, `.zip`, `.docx`, etc.):
     - MediaStore: `MediaStore.Downloads.EXTERNAL_CONTENT_URI`
     - Relative Path: `Download/LaptopTransfer/`
4. Resolves duplicate filenames:
   - Checks if `<fileName>` already exists in that folder.
   - If `landscape.jpg` exists, automatically generates `landscape (1).jpg`, `landscape (2).jpg`, etc.
   - Preserves original extension.
5. Creates a pending MediaStore record with `IS_PENDING = 1`.
6. Returns `200 OK`:
```json
{
  "transferId": "transfer-uuid-1234",
  "status": "READY",
  "resolvedFileName": "landscape (1).jpg",
  "targetFolder": "Pictures/LaptopTransfer/"
}
```

### 3.2 Step 2: Binary Streaming Upload
`POST /api/v1/transfer/upload?transferId=transfer-uuid-1234`

**Headers:**
- `Authorization`: `Bearer <serverAuthToken>`
- `X-BeamDrop-Sender-Id`: `<macbook-pro-uuid>`
- `Content-Length`: `12459800`
- `Content-Type`: `application/octet-stream`

**Body:**
Raw binary file stream transmitted chunk by chunk (e.g. 64 KB - 1 MB buffers).

**Android Processing During Upload:**
1. Holds `PARTIAL_WAKE_LOCK` and `WIFI_MODE_FULL_HIGH_PERF`.
2. Streams incoming payload directly into the MediaStore output stream.
3. Computes incremental SHA-256 digest in real-time.
4. Broadcasts progress updates (bytes transferred, speed, ETA) to the Foreground Service notification and Compose UI.

**Android Processing Upon Stream End:**
1. Compares computed SHA-256 against expected `sha256` from Init step.
2. If SHA-256 matches:
   - Sets `IS_PENDING = 0` on the MediaStore entry.
   - Android OS immediately triggers media indexer: the file appears in Google Photos / Gallery without manual intervention.
   - Appends entry to transfer history.
   - Updates ongoing notification: "Transfer complete: landscape (1).jpg saved to Pictures/LaptopTransfer/".
   - Returns `200 OK`:
     ```json
     {
       "transferId": "transfer-uuid-1234",
       "status": "COMPLETED",
       "fileName": "landscape (1).jpg",
       "folder": "Pictures/LaptopTransfer/",
       "bytesReceived": 12459800,
       "sha256": "e3b0c442..."
     }
     ```
3. If SHA-256 does NOT match:
   - Deletes incomplete MediaStore file.
   - Returns `422 Unprocessable Entity`: `{ "error": "Checksum mismatch" }`.

---

## 4. Diagnostics & Heartbeat

### `GET /api/v1/ping`
Returns receiver identity, pairing status, and battery state.
```json
{
  "status": "ONLINE",
  "version": 1,
  "deviceId": "moto-pad-60-pro-uuid",
  "deviceName": "Moto Pad 60 Pro",
  "freeSpaceBytes": 48293940224,
  "isServiceActive": true
}
```

### `POST /api/v1/unpair`
Revokes trust for the sending device.
