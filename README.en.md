<div align="center">

# 📬 MailControl

**A Pure Native, Self-Hosted Cross-Platform Multi-Account Email Workspace**

[![Go](https://img.shields.io/badge/Backend-Go%201.26%20%2B%20Gin%20%2B%20SQLite-00ADD8?style=flat-square&logo=go)](backend/)
[![Flutter](https://img.shields.io/badge/Client-Flutter%20Native%20(Windows%20%2B%20Android)-02569B?style=flat-square&logo=flutter)](app/)
[![Protocol](https://img.shields.io/badge/Protocol-IMAP%20%2B%20SMTP%20%2B%20SSE-10B981?style=flat-square)](#key-features)

[简体中文](README.md) | **English** | [日本語](README.ja.md) | [繁體中文](README.zh-TW.md)

</div>

---

## Understand MailControl in 1 Minute

If you juggle multiple email accounts (Gmail, Outlook, iCloud, QQ, NetEase 163, university or work mail), switching between different apps or configuring IMAP/SMTP separately on every device gets tedious quickly.

**MailControl** solves this with a **Single Go Backend + Native Desktop & Mobile Clients** architecture:

```text
  +--------------------+        HTTPS / LAN HTTP        +------------------------------+
  |  Windows Desktop   |  <-------------------------->  |      MailControl Server      |
  | (mailcontrol_app)  |    JWT + REST API + SSE Push   |  (Go + SQLite + IMAP/SMTP)   |
  +--------------------+                                +------------------------------+
                                                                        ^
  +--------------------+                                                |
  |   Android Mobile   |  <---------------------------------------------+
  | (app-release.apk)  |   Sign in once -> accounts, tags, rules & signatures sync
  +--------------------+
```

- **Pure Native, No WebView Wrapper**: Both the Windows app (`.exe`) and Android app (`.apk`) are compiled natively with Flutter.
- **Bind Once, Sync Everywhere**: Sign in with the same MailControl account on Windows and Android—your mailboxes, read states, colored tags, auto-rules, and signatures stay synchronized.
- **100% Self-Hosted & Private**: The backend is a single Go binary backed by SQLite. Run it locally on your PC with one click, or host it 24/7 on your own VPS.

---

## Key Features

- **All Major Email Providers Under One Account**: Built-in **12 presets** (Gmail, Outlook / Hotmail, iCloud, Yahoo, QQ / Foxmail, NetEase 163 / 126, Tencent / Aliyun / Feishu enterprise mail, Sina, plus custom IMAP/SMTP). Credentials are encrypted at rest with **AES-256-GCM**.
- **Adaptive Native UI & Smart Dark Mode**:
  - **Windows Desktop**: Seamless custom frameless title bar + classic 3-pane workspace + one-click local server launch from the login screen.
  - **Android Mobile**: Drawer navigation + responsive list/detail flow + pull-to-refresh + floating compose button.
  - **Smart Dark Mode Email Rendering**: Automatically adapts bright HTML email backgrounds, dark text, and light borders for comfortable night reading—plus a one-click **"Light Paper"** toggle for emails with transparent dark-text PNG logos.
- **Free In-Place HTML Translation**: Multi-provider fallback (Edge / Google / MyMemory) with **server-side `translated_html` caching**. Translates subject & body **directly inside the original HTML layout** (preserving links, bold text, buttons, and formatting) with an instant **"Original / Translated"** toggle.
- **Native System Notifications (While Signed In)**:
  - **Windows**: Native Win32 Toast notifications; clicking opens/focuses the window on that email.
  - **Android**: High-priority heads-up banners showing the sender, account, and auto-assigned category tag (e.g., `[Verification Code]`).
- **Auto-Classification Rules & Tag Unread Badges**:
  - Visual rule builder with one-click preset imports (verification codes, invoices, dev alerts, shipping, security alerts, newsletters) and one-click retroactive execution on existing mail.
  - Sidebar **Tag Categories** display real-time unread count pills.
- **Saved Server URL History**: Automatically remembers verified/logged-in backend URLs for one-click switching.
- **Compatibility & Deduplication Built In**:
  - Automatically sends RFC 2971 **IMAP ID** (required by NetEase 163/126) and decodes legacy `GB18030 / GBK / GB2312 / Big5` charsets.
  - Skips Gmail virtual aggregate folders (`[Gmail]/All Mail`, `Important`, `Starred`) to eliminate duplicate email copies and out-of-sync unread counts, while syncing read/star states across any sibling copies.
- **Built-in Web Admin Panel (`/admin`)**: Monitor system overview, per-account sync status, toggle public registration, manage users, and download SQLite database backups.

---

## Beginner Quick Start (Choose One of 3 Modes)

### Mode A: Standalone on One Windows PC (Easiest)

No server or domain required—**3 steps to get started**:

1. Keep `mailcontrol_app.exe` and `mailcontrol-server.exe` in the same folder and launch `mailcontrol_app.exe`.
2. On the login screen, click **"一键启动本地服务" (Start Local Server)**. It launches `http://127.0.0.1:8080` locally and persists your local SQLite database at `%LOCALAPPDATA%\MailControl\local_data`.
3. Switch to **"Register"**, create a local user account, sign in, and click **"+"** in the sidebar to bind your email accounts.

> **Note for Beginners**: The local database (`127.0.0.1:8080`) is completely separate from any remote/cloud server. If you previously registered on a cloud server, create a local account when testing locally (or switch the server URL back to your cloud URL to sign in with your cloud account).

---

### Mode B: PC Host + Phone Sync Over Home/Office Wi-Fi

1. **Start the server on your PC**: Click "Start Local Server" in the Windows app, or run `mailcontrol-server.exe` directly.
2. **Allow Port `8080` in Windows Firewall**: Make sure inbound TCP port `8080` is allowed.
3. **Find your PC's LAN IP**: Run `ipconfig` in Command Prompt / PowerShell and note your IPv4 address (e.g., `192.168.1.100`).
4. **Connect from Android**:
   - Install `app-release.apk` on your phone.
   - Tap the **Server** button on the login screen, enter `http://192.168.1.100:8080`, and tap **Test Connection**.
   - Sign in with the same MailControl account used on your PC.

---

### Mode C: Self-Host on a Cloud VPS with HTTPS (Recommended for 24/7 Sync)

Assuming a Linux VPS (`amd64` or `arm64`) and a domain such as `mail.example.com`:

1. **Cross-compile the Go server** (from `backend/`):
   ```powershell
   # Use GOARCH=amd64 for x86_64 VPS, or GOARCH=arm64 for ARM64 VPS
   $env:GOOS="linux"
   $env:GOARCH="amd64"
   go build -o mailcontrol-server ./cmd/server
   ```
2. **Run with `systemd`** (`/etc/systemd/system/mailcontrol.service`):
   ```ini
   [Unit]
   Description=MailControl Backend Server
   After=network.target

   [Service]
   Type=simple
   WorkingDirectory=/opt/mailcontrol
   Environment=HOST=127.0.0.1
   Environment=PORT=18080
   Environment=DATA_DIR=/opt/mailcontrol/data
   ExecStart=/opt/mailcontrol/mailcontrol-server
   Restart=always
   RestartSec=3

   [Install]
   WantedBy=multi-user.target
   ```
   ```bash
   sudo mkdir -p /opt/mailcontrol/data
   sudo chmod +x /opt/mailcontrol/mailcontrol-server
   sudo systemctl daemon-reload && sudo systemctl enable --now mailcontrol
   ```
3. **Reverse proxy with Caddy (automatic HTTPS)**:
   ```caddyfile
   mail.example.com {
       reverse_proxy 127.0.0.1:18080 {
           flush_interval -1
       }
   }
   ```
   > `flush_interval -1` prevents proxy buffering so real-time SSE notifications arrive instantly.
4. **Connect Clients**: Enter `https://mail.example.com` in both Windows and Android clients. Verified URLs are saved under Frequent Servers for quick switching.

---

## How to Get Email App Passwords / Authorization Codes

> Most providers reject your regular web login password for IMAP/SMTP access. Generate an **App Password / Authorization Code** instead:

| Provider | IMAP / SMTP (Auto-filled) | Step-by-Step Setup |
| :--- | :--- | :--- |
| **Gmail** | `imap.gmail.com:993` (SSL)<br>`smtp.gmail.com:465` (SSL) | Google Account → **Security** → Enable **2-Step Verification** → Search **App Passwords** → Create an app password (e.g., `MailControl`) → Copy the **16-character code** (without spaces). |
| **Outlook / Hotmail** | `outlook.office365.com:993` (SSL)<br>`smtp.office365.com:587` (STARTTLS) | Outlook Web → **Settings (Gear)** → **Mail** → **Sync email** → Enable IMAP access. If 2FA is enabled, create an App Password in Microsoft Account Security. |
| **iCloud** | `imap.mail.me.com:993` (SSL)<br>`smtp.mail.me.com:587` (STARTTLS) | Sign in at [account.apple.com](https://account.apple.com) → **Sign-In and Security** → **App-Specific Passwords** → Generate a password and paste it into MailControl. |
| **QQ / Foxmail** | `imap.qq.com:993` (SSL)<br>`smtp.qq.com:465` (SSL) | QQ Mail Web → **Settings** → **Account** → Enable **IMAP/SMTP service** → Verify via SMS to get the **16-character authorization code**. |
| **NetEase 163 / 126** | `imap.163.com:993` (SSL)<br>`smtp.163.com:465` (SSL) | NetEase Web → **Settings** → **POP3/SMTP/IMAP** → Enable **IMAP/SMTP** → Generate a new **Authorization Password** (IMAP ID is handled automatically). |

---

## Everyday Features Explained

- **Signature Templates**: Custom sign-offs appended to the bottom of emails you compose. You can bind different signatures to specific mailboxes (e.g., work vs. personal), set a global fallback signature, or insert any signature on demand while composing. Leave empty if you do not need signatures.
- **Auto-Rules & Tag Badges**: Click **"Auto Rules" → "Import Presets"** to classify incoming mail automatically and run rules against existing messages; unread counts appear directly on each tag in the sidebar.
- **In-Place Translation**: Click the **Translate icon** in the message toolbar and pick a target language. MailControl translates text nodes inside the original HTML layout and lets you switch back and forth via **"View Original / View Translated"**.
- **Web Admin Console (`/admin`)**: Visit `http://127.0.0.1:8080/admin` or `https://mail.example.com/admin`. The **first registered user is automatically granted administrator privileges** to inspect sync status, toggle public sign-ups, reset user passwords, or download SQLite backups.

---

## FAQ & Troubleshooting

<details>
<summary><b>Q1: "Invalid account or password" after clicking "Start Local Server"?</b></summary>

The local server uses an independent SQLite database under `%LOCALAPPDATA%\MailControl\local_data`. Register a local account on first local use, or point the server URL to your cloud backend if you want to sign in with your cloud account.
</details>

<details>
<summary><b>Q2: Phone cannot connect to the PC server over Wi-Fi?</b></summary>

Ensure both devices are on the same Wi-Fi network, `mailcontrol-server.exe` is running on the PC, and Windows Firewall allows inbound TCP traffic on port `8080`.
</details>

<details>
<summary><b>Q3: No system popup notification when new mail arrives?</b></summary>

- **Windows**: Make sure Windows Notifications are enabled and **Do Not Disturb** is off.
- **Android**: Allow the **Notifications** permission when prompted after login (Android 13+), or enable it manually in System App Settings.
</details>

<details>
<summary><b>Q4: An email looks hard to read in Dark Mode (e.g., dark PNG logo on dark background)?</b></summary>

Click **"浅色信纸" (Light Paper)** in the top-right corner of the message card to view that email on a clean white background while keeping the rest of the app in Dark Mode.
</details>

---

## Server Environment Variables

If `JWT_SECRET` or `ENC_KEY` is omitted, the backend auto-generates and saves them to `DATA_DIR/secrets.json` on first run:

| Variable | Default | Description |
| :--- | :--- | :--- |
| `HOST` | `0.0.0.0` | Listen address (`127.0.0.1` recommended behind Caddy/Nginx) |
| `PORT` | `8080` | HTTP listen port |
| `DATA_DIR` | `./data` | Directory for `mailcontrol.db`, attachments, and `secrets.json` |
| `JWT_SECRET` | Auto-generated | JWT signing secret |
| `ENC_KEY` | Auto-generated | AES-256-GCM key for mailbox passwords (do not rotate without re-entering credentials) |
| `DEFAULT_SYNC_INTERVAL` | `180` | Default background sync interval in seconds (minimum `30`) |

---

## Building from Source

- **Requirements**: Go 1.24+ (pure Go, no CGO), Flutter 3.27+, JDK 17 + Android SDK (for `.apk`), Visual Studio C++ Desktop Build Tools + **Windows Developer Mode** enabled (for `.exe`).
- **Run Tests**:
  ```powershell
  cd backend && go test ./...
  cd ..\app && flutter analyze && flutter test
  ```
- **Build All Targets (Windows + Android)**:
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\scripts\build-all.ps1
  ```
  Outputs:
  - Windows: `app\build\windows\x64\runner\Release\mailcontrol_app.exe` (with `mailcontrol-server.exe`)
  - Android: `app\build\app\outputs\flutter-apk\app-release.apk`

---

## Project Layout

```text
mailcontrol/
├── backend/                  # Go backend (Gin + SQLite + IMAP/SMTP + Rules + Translator + SSE + /admin)
├── app/                      # Flutter native app (Windows desktop + Android mobile)
├── scripts/                  # Build automation script (build-all.ps1)
├── README.md                 # Simplified Chinese
├── README.en.md              # English
├── README.ja.md              # Japanese
└── README.zh-TW.md           # Traditional Chinese
```
