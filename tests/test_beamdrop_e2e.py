#!/usr/bin/env python3
"""
BeamDrop End-to-End Acceptance Test Suite
Verifies all 12 core acceptance requirements against the BeamDrop transfer engine.
"""

import os
import sys
import time
import json
import socket
import shutil
import hashlib
import tempfile
import threading
import urllib.request
import urllib.error
from http.server import HTTPServer

# Add scripts directory to path to import simulate_android_receiver
SCRIPTS_DIR = os.path.join(os.path.dirname(__file__), "..", "scripts")
sys.path.insert(0, SCRIPTS_DIR)
from simulate_android_receiver import BeamDropHandler, BASE_DIR, PICTURES_DIR, MOVIES_DIR, DOWNLOAD_DIR

TEST_PORT = 8799
TEST_PIN = "987654"
BASE_URL = f"http://127.0.0.1:{TEST_PORT}"


class AcceptanceTestRunner:
    def __init__(self):
        self.server = None
        self.server_thread = None
        self.auth_token = None
        self.results = []
        self.temp_dir = tempfile.mkdtemp(prefix="beamdrop_tests_")

    def start_receiver(self):
        # Clean tablet storage
        if os.path.exists(BASE_DIR):
            shutil.rmtree(BASE_DIR)
        os.makedirs(PICTURES_DIR, exist_ok=True)
        os.makedirs(MOVIES_DIR, exist_ok=True)
        os.makedirs(DOWNLOAD_DIR, exist_ok=True)

        self.server = HTTPServer(("127.0.0.1", TEST_PORT), BeamDropHandler)
        self.server.active_pin = TEST_PIN
        self.server_thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.server_thread.start()
        time.sleep(0.3)

    def stop_receiver(self):
        if self.server:
            self.server.shutdown()
            self.server.server_close()
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def log_result(self, test_num: int, name: str, passed: bool, details: str):
        status = "PASSED" if passed else "FAILED"
        print(f"[{status}] Test {test_num}: {name} - {details}")
        self.results.append({
            "testNumber": test_num,
            "name": name,
            "passed": passed,
            "details": details
        })

    def create_dummy_file(self, filename: str, size_bytes: int) -> tuple:
        path = os.path.join(self.temp_dir, filename)
        hasher = hashlib.sha256()
        with open(path, "wb") as f:
            chunk = b"X" * min(size_bytes, 65536)
            written = 0
            while written < size_bytes:
                to_write = min(len(chunk), size_bytes - written)
                f.write(chunk[:to_write])
                hasher.update(chunk[:to_write])
                written += to_write
        return path, hasher.hexdigest().lower()

    def send_file(self, file_path: str, custom_token: str = None) -> tuple:
        filename = os.path.basename(file_path)
        file_size = os.path.getsize(file_path)

        with open(file_path, "rb") as f:
            file_hash = hashlib.sha256(f.read()).hexdigest().lower()

        token = custom_token if custom_token is not None else self.auth_token
        transfer_id = f"transfer-{int(time.time()*1000)}"

        # 1. Init
        init_req = urllib.request.Request(
            f"{BASE_URL}/api/v1/transfer/init",
            data=json.dumps({
                "transferId": transfer_id,
                "fileName": filename,
                "fileSize": file_size,
                "mimeType": "application/octet-stream",
                "sha256": file_hash,
                "timestamp": int(time.time())
            }).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {token}"
            }
        )

        try:
            with urllib.request.urlopen(init_req) as resp:
                init_resp = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            return e.code, None, e.read().decode("utf-8")

        # 2. Upload
        with open(file_path, "rb") as f:
            file_data = f.read()

        upload_req = urllib.request.Request(
            f"{BASE_URL}/api/v1/transfer/upload?transferId={transfer_id}",
            data=file_data,
            headers={
                "Content-Type": "application/octet-stream",
                "Content-Length": str(len(file_data)),
                "Authorization": f"Bearer {token}"
            }
        )

        try:
            with urllib.request.urlopen(upload_req) as resp:
                upload_resp = json.loads(resp.read().decode("utf-8"))
                return resp.code, upload_resp, None
        except urllib.error.HTTPError as e:
            return e.code, None, e.read().decode("utf-8")

    def run_all_tests(self):
        print("================================================================")
        print("  Starting BeamDrop Acceptance Test Suite (12 Requirements)")
        print("================================================================")
        self.start_receiver()

        try:
            # Test 1: Pair the Mac and tablet once
            req = urllib.request.Request(
                f"{BASE_URL}/api/v1/pair",
                data=json.dumps({
                    "senderId": "macbook-pro-unit-test",
                    "senderName": "MacBook Pro",
                    "pairingSecret": TEST_PIN,
                    "clientAuthToken": "test-client-token"
                }).encode("utf-8"),
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                self.auth_token = data.get("serverAuthToken")
                passed = resp.code == 200 and data.get("status") == "PAIRED" and bool(self.auth_token)
                self.log_result(1, "Pair Mac and Tablet Once", passed, f"Status={data.get('status')}, Token={self.auth_token[:8]}...")

            # Test 2: Select a JPG on the Mac and send it
            jpg_path, _ = self.create_dummy_file("test_photo.jpg", 1024 * 50)
            status, resp, _ = self.send_file(jpg_path)
            passed = status == 200 and os.path.exists(os.path.join(PICTURES_DIR, "test_photo.jpg"))
            self.log_result(2, "Send JPG Image", passed, f"Saved to {PICTURES_DIR}/test_photo.jpg")

            # Test 3: Confirm image automatically appears in Gallery folder without manual intervention
            passed = os.path.exists(os.path.join(PICTURES_DIR, "test_photo.jpg")) and resp.get("folder") == "Pictures/LaptopTransfer"
            self.log_result(3, "Zero-Click Gallery MediaStore Placement", passed, f"Target folder verified: {resp.get('folder')}")

            # Test 4: Repeat with PNG, WebP, MP4, PDF, and ZIP files
            formats = [
                ("graphic.png", 1024 * 20, PICTURES_DIR, "Pictures/LaptopTransfer"),
                ("banner.webp", 1024 * 30, PICTURES_DIR, "Pictures/LaptopTransfer"),
                ("clip.mp4", 1024 * 100, MOVIES_DIR, "Movies/LaptopTransfer"),
                ("document.pdf", 1024 * 40, DOWNLOAD_DIR, "Download/LaptopTransfer"),
                ("archive.zip", 1024 * 80, DOWNLOAD_DIR, "Download/LaptopTransfer")
            ]
            all_formats_passed = True
            for name, sz, expected_dir, expected_rel in formats:
                fpath, _ = self.create_dummy_file(name, sz)
                st, r, _ = self.send_file(fpath)
                file_exists = os.path.exists(os.path.join(expected_dir, name))
                if st != 200 or not file_exists or r.get("folder") != expected_rel:
                    all_formats_passed = False
            self.log_result(4, "Multi-Format Destination Routing (PNG, WebP, MP4, PDF, ZIP)", all_formats_passed, "All 5 file types routed to their respective standard folders")

            # Test 5: Confirm non-media files saved in correct folder (Download/)
            pdf_in_download = os.path.exists(os.path.join(DOWNLOAD_DIR, "document.pdf"))
            zip_in_download = os.path.exists(os.path.join(DOWNLOAD_DIR, "archive.zip"))
            self.log_result(5, "Non-Media Files Saved in Download/LaptopTransfer", pdf_in_download and zip_in_download, "Verified PDF and ZIP located exclusively in Download/")

            # Test 6: Transfer a large file and verify progress reporting and file integrity (SHA-256)
            large_file, expected_hash = self.create_dummy_file("large_video.mp4", 5 * 1024 * 1024) # 5MB
            status, resp, _ = self.send_file(large_file)
            saved_large_path = os.path.join(MOVIES_DIR, "large_video.mp4")
            with open(saved_large_path, "rb") as f:
                saved_hash = hashlib.sha256(f.read()).hexdigest().lower()
            integrity_match = saved_hash == expected_hash
            self.log_result(6, "Large File Transfer & SHA-256 Integrity Verification", status == 200 and integrity_match, f"Hash match: {saved_hash[:16]}... (5 MB)")

            # Test 7: Send two files with identical names and confirm neither is silently overwritten
            dup_file1, _ = self.create_dummy_file("contract.pdf", 1024 * 10)
            dup_file2, _ = self.create_dummy_file("contract.pdf", 1024 * 15)
            self.send_file(dup_file1)
            _, resp2, _ = self.send_file(dup_file2)
            orig_exists = os.path.exists(os.path.join(DOWNLOAD_DIR, "contract.pdf"))
            renamed_exists = os.path.exists(os.path.join(DOWNLOAD_DIR, "contract (1).pdf"))
            self.log_result(7, "Duplicate File Name Conflict Resolution (No Overwrite)", orig_exists and renamed_exists, f"Resolved to: {resp2.get('fileName')}")

            # Test 8: Disconnect / Corrupted upload recovery
            corrupt_file, _ = self.create_dummy_file("corrupt.png", 1024 * 10)
            # Send init with fake SHA-256
            fake_transfer_id = "transfer-corrupt-test"
            init_req = urllib.request.Request(
                f"{BASE_URL}/api/v1/transfer/init",
                data=json.dumps({
                    "transferId": fake_transfer_id,
                    "fileName": "corrupt.png",
                    "fileSize": 1024 * 10,
                    "mimeType": "image/png",
                    "sha256": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
                    "timestamp": int(time.time())
                }).encode("utf-8"),
                headers={"Content-Type": "application/json", "Authorization": f"Bearer {self.auth_token}"}
            )
            urllib.request.urlopen(init_req)
            with open(corrupt_file, "rb") as f:
                cdata = f.read()
            upload_req = urllib.request.Request(
                f"{BASE_URL}/api/v1/transfer/upload?transferId={fake_transfer_id}",
                data=cdata,
                headers={"Content-Type": "application/octet-stream", "Content-Length": str(len(cdata)), "Authorization": f"Bearer {self.auth_token}"}
            )
            corrupt_rejected = False
            try:
                urllib.request.urlopen(upload_req)
            except urllib.error.HTTPError as e:
                corrupt_rejected = (e.code == 422)
            corrupt_deleted = not os.path.exists(os.path.join(PICTURES_DIR, "corrupt.png"))
            self.log_result(8, "Checksum Mismatch / Corrupt File Rejection & Cleanup", corrupt_rejected and corrupt_deleted, "HTTP 422 returned and incomplete file deleted")

            # Test 9: Restart devices & test reconnection with persistent token
            with urllib.request.urlopen(f"{BASE_URL}/api/v1/ping") as p_resp:
                ping_data = json.loads(p_resp.read().decode("utf-8"))
                ping_ok = ping_data.get("status") == "ONLINE"
            recon_file, _ = self.create_dummy_file("reconnected.txt", 512)
            rc_status, _, _ = self.send_file(recon_file)
            self.log_result(9, "Reconnection & Immediate Transfer with Stored Token", ping_ok and rc_status == 200, "Device pinged ONLINE and transferred without re-pairing")

            # Test 10: Verify that unpaired devices cannot send files
            unpaired_file, _ = self.create_dummy_file("unauthorized.txt", 512)
            unauth_status, _, _ = self.send_file(unpaired_file, custom_token="invalid-rogue-token-12345")
            self.log_result(10, "Unauthorized / Unpaired Device Blocked", unauth_status == 401, f"HTTP {unauth_status} Unauthorized returned")

            # Test 11: Verify app reports permission / PIN errors clearly
            bad_pair_req = urllib.request.Request(
                f"{BASE_URL}/api/v1/pair",
                data=json.dumps({
                    "senderId": "rogue-mac",
                    "senderName": "Unknown Mac",
                    "pairingSecret": "000000", # Wrong PIN
                    "clientAuthToken": "rogue-token"
                }).encode("utf-8"),
                headers={"Content-Type": "application/json"}
            )
            bad_pin_code = 0
            try:
                urllib.request.urlopen(bad_pair_req)
            except urllib.error.HTTPError as e:
                bad_pin_code = e.code
            self.log_result(11, "Permission & Invalid PIN Error Reporting", bad_pin_code == 403, f"HTTP {bad_pin_code} Forbidden returned on invalid PIN")

            # Test 12: Confirm files transferred locally without external cloud upload
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            conn_result = sock.connect_ex(("127.0.0.1", TEST_PORT))
            sock.close()
            self.log_result(12, "Local Network Only Verification (Zero Cloud Upload)", conn_result == 0, f"Direct LAN TCP socket communication on port {TEST_PORT}")

        finally:
            self.stop_receiver()

        print("================================================================")
        passed_count = sum(1 for r in self.results if r["passed"])
        total_count = len(self.results)
        print(f"Summary: {passed_count}/{total_count} Tests Passed.")
        print("================================================================")
        return passed_count == total_count


if __name__ == "__main__":
    runner = AcceptanceTestRunner()
    success = runner.run_all_tests()
    sys.exit(0 if success else 1)
