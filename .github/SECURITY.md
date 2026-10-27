# Security Policy

BeamDrop takes the security and privacy of its users very seriously. Since BeamDrop is engineered as a 100% peer-to-peer local network bridge with zero cloud telemetry, security focuses on local network isolation, cryptographic device pairing, and authenticated HTTP/SSE endpoints.

---

## Supported Versions

Only the latest release receives active security patches. We recommend all users keep their macOS and Android applications updated to the latest tag.

| Version | Supported          |
| :------ | :----------------- |
| 1.4.x   | :white_check_mark: |
| 1.3.x   | :white_check_mark: |
| < 1.3.0 | :x:                |

---

## Security Model & Architecture

BeamDrop enforces several defense-in-depth measures:

1. **Local Wi-Fi Only**:
   - All file transfers, clipboard sync, remote commands, webcam streaming, and notifications communicate strictly over the local area network (`LAN`).
   - No external servers, cloud databases, or third-party relay brokers are used.
2. **Cryptographic Device Pairing**:
   - Pairing is initiated with an ephemeral 6-digit PIN code.
   - Upon successful verification, 256-bit cryptographic bearer tokens (`serverAuthToken`, `clientAuthToken`) are generated and stored in the macOS Keychain and Android KeyStore.
3. **Endpoint Authorization**:
   - All administrative and file manipulation endpoints (`/api/v1/transfer/*`, `/api/v1/scripts/*`, `/api/v1/adb/*`, `/api/v1/webcam/*`) validate the `Authorization: Bearer <token>` header. Unauthorized requests are rejected with `401 Unauthorized`.
4. **Data Integrity**:
   - Files transferred across the network are verified using bit-for-bit SHA-256 hash checksums before final commit to storage.

---

## Reporting a Vulnerability

If you discover a security vulnerability within BeamDrop, please report it responsibly:

1. **GitHub Private Vulnerability Advisory** (Preferred):
   - Navigate to [Security Advisories](https://github.com/ttushaarr/Beamdrop/security/advisories/new) on GitHub and submit a private report.
2. **Email**:
   - Send details to `ttushaarr@gmail.com` with the subject line `[BeamDrop Security Vulnerability]`.

### What to Include in Your Report:
- A description of the issue and potential security impact.
- Step-by-step instructions or Proof of Concept (PoC) to reproduce the vulnerability.
- Affected platforms (macOS, Android, or both).

### Our Commitment:
- **Initial Response**: We will acknowledge receipt of your vulnerability report within 24–48 hours.
- **Remediation & Patch**: We will work on a fix in a private branch and coordinate a disclosure timeline before releasing a patch.
