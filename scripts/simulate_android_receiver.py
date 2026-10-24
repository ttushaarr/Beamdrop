#!/usr/bin/env python3
"""
BeamDrop Android Receiver Simulator (Python Twin)
Replicates the exact protocol, storage paths, duplicate handling,
and cryptographic verification of the Android Kotlin BeamDrop receiver.
"""

import os
import sys
import json
import time
import hashlib
import argparse
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

DEFAULT_PORT = 8765
DEFAULT_PIN = "123456"
SERVER_TOKEN = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

# Target storage directories matching Android MediaStore
BASE_DIR = os.environ.get("BEAMDROP_STORAGE", "/tmp/BeamDrop_Tablet_Storage")
PICTURES_DIR = os.path.join(BASE_DIR, "Pictures", "LaptopTransfer")
MOVIES_DIR = os.path.join(BASE_DIR, "Movies", "LaptopTransfer")
DOWNLOAD_DIR = os.path.join(BASE_DIR, "Download", "LaptopTransfer")

os.makedirs(PICTURES_DIR, exist_ok=True)
os.makedirs(MOVIES_DIR, exist_ok=True)
os.makedirs(DOWNLOAD_DIR, exist_ok=True)

IMAGE_EXTENSIONS = {"jpg", "jpeg", "png", "webp", "heic", "heif", "gif", "avif", "bmp", "tiff"}
VIDEO_EXTENSIONS = {"mp4", "mkv", "mov", "webm", "avi", "3gp", "m4v"}

# In-memory session state
paired_devices = {}
pending_transfers = {}
transfer_history = []


def resolve_folder(filename: str) -> str:
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    if ext in IMAGE_EXTENSIONS:
        return PICTURES_DIR, "Pictures/LaptopTransfer"
    elif ext in VIDEO_EXTENSIONS:
        return MOVIES_DIR, "Movies/LaptopTransfer"
    else:
        return DOWNLOAD_DIR, "Download/LaptopTransfer"


def resolve_unique_name(folder_path: str, filename: str) -> str:
    """Duplicate-safe naming: prevents overwriting by appending (1), (2), etc."""
    if not os.path.exists(os.path.join(folder_path, filename)):
        return filename

    if "." in filename:
        base, ext = filename.rsplit(".", 1)
        ext = "." + ext
    else:
        base, ext = filename, ""

    counter = 1
    while True:
        candidate = f"{base} ({counter}){ext}"
        if not os.path.exists(os.path.join(folder_path, candidate)):
            return candidate
        counter += 1


class BeamDropHandler(BaseHTTPRequestHandler):
    server_version = "BeamDropReceiver/1.0 (Moto Pad 60 Pro Simulator)"

    def _send_json(self, status: int, data: dict):
        body = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/api/v1/ping":
            self._send_json(200, {
                "status": "ONLINE",
                "version": 1,
                "deviceId": "moto-pad-60-pro-sim",
                "deviceName": "Moto Pad 60 Pro",
                "freeSpaceBytes": 64 * 1024 * 1024 * 1024,
                "isServiceActive": True
            })
        else:
            self._send_json(404, {"error": "Not found"})

    def do_POST(self):
        url = urlparse(self.path)

        # 1. Pairing
        if url.path == "/api/v1/pair":
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length).decode("utf-8"))
            pin = body.get("pairingSecret", "").strip()
            sender_id = body.get("senderId", "")
            sender_name = body.get("senderName", "MacBook Pro")
            client_token = body.get("clientAuthToken", "")

            if pin != self.server.active_pin:
                self._send_json(403, {"error": "Invalid pairing secret"})
                return

            paired_devices[sender_id] = {
                "senderName": sender_name,
                "clientToken": client_token,
                "pairedAt": time.time()
            }
            print(f"[AUTH] Successfully paired with {sender_name} ({sender_id})")

            self._send_json(200, {
                "status": "PAIRED",
                "receiverId": "moto-pad-60-pro-sim",
                "receiverName": "Moto Pad 60 Pro",
                "serverAuthToken": SERVER_TOKEN
            })
            return

        # 2. Transfer Init
        if url.path == "/api/v1/transfer/init":
            auth = self.headers.get("Authorization", "")
            token = auth.replace("Bearer ", "").strip()
            if token != SERVER_TOKEN:
                self._send_json(401, {"error": "Unauthorized: Device not paired"})
                return

            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length).decode("utf-8"))
            transfer_id = body["transferId"]
            filename = body["fileName"]
            file_size = body["fileSize"]
            sha256 = body["sha256"]

            dest_folder, relative_path = resolve_folder(filename)
            unique_name = resolve_unique_name(dest_folder, filename)

            pending_transfers[transfer_id] = {
                "fileName": filename,
                "resolvedName": unique_name,
                "fileSize": file_size,
                "sha256": sha256,
                "destFolder": dest_folder,
                "relativePath": relative_path,
                "timestamp": time.time()
            }

            self._send_json(200, {
                "transferId": transfer_id,
                "status": "READY",
                "resolvedFileName": unique_name,
                "targetFolder": relative_path
            })
            return

        # 3. Binary Streaming Upload
        if url.path == "/api/v1/transfer/upload":
            auth = self.headers.get("Authorization", "")
            token = auth.replace("Bearer ", "").strip()
            if token != SERVER_TOKEN:
                self._send_json(401, {"error": "Unauthorized"})
                return

            query = parse_qs(url.query)
            transfer_id = query.get("transferId", [None])[0]
            if not transfer_id or transfer_id not in pending_transfers:
                self._send_json(400, {"error": "Invalid or expired transferId"})
                return

            info = pending_transfers.pop(transfer_id)
            expected_size = info["fileSize"]
            expected_sha = info["sha256"].lower()
            target_path = os.path.join(info["destFolder"], info["resolvedName"])

            hasher = hashlib.sha256()
            received_bytes = 0
            chunk_size = 64 * 1024

            try:
                with open(target_path, "wb") as f:
                    while received_bytes < expected_size:
                        to_read = min(chunk_size, expected_size - received_bytes)
                        chunk = self.rfile.read(to_read)
                        if not chunk:
                            break
                        f.write(chunk)
                        hasher.update(chunk)
                        received_bytes += len(chunk)

                computed_sha = hasher.hexdigest().lower()
                if computed_sha != expected_sha:
                    if os.path.exists(target_path):
                        os.remove(target_path)
                    print(f"[ERROR] SHA-256 mismatch for {info['resolvedName']}: expected {expected_sha}, got {computed_sha}")
                    self._send_json(422, {"error": "Checksum verification failed"})
                    return

                print(f"[SUCCESS] Received {info['resolvedName']} ({received_bytes} bytes) -> {info['relativePath']}/")
                transfer_history.append({
                    "id": transfer_id,
                    "fileName": info["resolvedName"],
                    "folder": info["relativePath"],
                    "size": received_bytes,
                    "sha256": computed_sha,
                    "timestamp": time.time()
                })

                self._send_json(200, {
                    "transferId": transfer_id,
                    "status": "COMPLETED",
                    "fileName": info["resolvedName"],
                    "folder": info["relativePath"],
                    "bytesReceived": received_bytes,
                    "sha256": computed_sha
                })

            except Exception as e:
                if os.path.exists(target_path):
                    os.remove(target_path)
                print(f"[ERROR] Upload interrupted: {e}")
                self._send_json(500, {"error": str(e)})
            return

        # 4. Clipboard Sync
        if url.path == "/api/v1/clipboard":
            auth = self.headers.get("Authorization", "")
            token = auth.replace("Bearer ", "").strip()
            if token != SERVER_TOKEN:
                self._send_json(401, {"error": "Unauthorized"})
                return

            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length).decode("utf-8")) if length > 0 else {}
            text = body.get("text", "")
            print(f"[CLIPBOARD] Received clipboard from Mac: \"{text[:40]}\" ({len(text)} chars)")
            self._send_json(200, {"status": "SYNCED", "timestamp": time.time()})
            return

        # 5. Unpair
        if url.path == "/api/v1/unpair":
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length).decode("utf-8")) if length > 0 else {}
            sender_id = body.get("senderId", "")
            if sender_id in paired_devices:
                del paired_devices[sender_id]
            self._send_json(200, {"status": "UNPAIRED"})
            return

        self._send_json(404, {"error": "Not found"})

    def log_message(self, format, *args):
        # Concise logging
        pass


def run_server(port=DEFAULT_PORT, pin=DEFAULT_PIN):
    server = HTTPServer(("0.0.0.0", port), BeamDropHandler)
    server.active_pin = pin
    print(f"==================================================")
    print(f"  BeamDrop Tablet Receiver Simulator (Moto Pad 60 Pro)")
    print(f"==================================================")
    print(f"  Listening on: http://0.0.0.0:{port}")
    print(f"  Active Pairing PIN: {pin}")
    print(f"  Storage Root: {BASE_DIR}")
    print(f"    - Photos/Images: {PICTURES_DIR}")
    print(f"    - Movies/Videos: {MOVIES_DIR}")
    print(f"    - Downloads:     {DOWNLOAD_DIR}")
    print(f"==================================================")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping receiver...")
        server.server_close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="BeamDrop Receiver Simulator")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Port to listen on (default: 8765)")
    parser.add_argument("--pin", type=str, default=DEFAULT_PIN, help="6-digit pairing PIN (default: 123456)")
    args = parser.parse_args()
    run_server(args.port, args.pin)
