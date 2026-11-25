<div align="center">

# 📬 MailControl

**完全原生、開源可自建的跨平台多帳號電子郵件統一管理系統**

[![Go](https://img.shields.io/badge/Backend-Go%201.26%20%2B%20Gin%20%2B%20SQLite-00ADD8?style=flat-square&logo=go)](backend/)
[![Flutter](https://img.shields.io/badge/Client-Flutter%20Native%20(Windows%20%2B%20Android)-02569B?style=flat-square&logo=flutter)](app/)
[![Protocol](https://img.shields.io/badge/Protocol-IMAP%20%2B%20SMTP%20%2B%20SSE-10B981?style=flat-square)](#核心功能一覽)

[简体中文](README.md) | [English](README.en.md) | [日本語](README.ja.md) | **繁體中文**

</div>

---

## 一分鐘看懂 MailControl

平時你可能同時擁有 Gmail、Outlook、iCloud、學校信箱或公司信箱——每次收驗證碼或找帳單都要在不同 App 與網頁之間切換，換台裝置還得全部重新綁定一次。

**MailControl** 透過 **「單一 Go 後端 ＋ 雙端原生用戶端」** 幫你把所有信箱整合在一起：

```text
  +--------------------+         HTTPS / 區網 HTTP         +------------------------------+
  |  Windows 桌面端    |  <----------------------------->  |      MailControl 後端        |
  | (mailcontrol_app)  |     JWT 登入 + REST API + SSE     |  (Go + SQLite + IMAP/SMTP)   |
  +--------------------+                                   +------------------------------+
                                                                           ^
  +--------------------+                                                   |
  |   Android 手機端   |  <------------------------------------------------+
  | (app-release.apk)  |    登入同一個帳號，信箱、郵件、標籤、規則與簽名自動同步
  +--------------------+
```

- **非網頁套殼**：Windows 桌面端（`.exe`）與 Android 手機端（`.apk`）皆以 Flutter 原生編譯，啟動迅速、操作流暢。
- **綁定一次，多端同步**：只要登入同一組 MailControl 帳號，電腦與手機之間的所有綁定信箱、已讀狀態、彩色標籤、自動規則與簽名模板全部自動同步。
- **資料完全掌握在自己手中**：後端僅為單一 Go 執行檔搭配 SQLite 資料庫，可在電腦單機一鍵啟動，也能部署到自己的雲端主機 24 小時背景收信。

---

## 核心功能一覽

- **單一帳號管理多種主流信箱**：內建 **12 類主流信箱一鍵預設**（Gmail、Outlook / Hotmail、iCloud、Yahoo、QQ / Foxmail、網易 163 / 126、騰訊/阿里/飛書企業郵、新浪及自訂 IMAP/SMTP），授權密碼採用 **AES-256-GCM** 加密儲存。
- **原生雙端介面 & 智慧深色模式**：
  - **Windows 桌面端**：無邊框融合標題列 ＋ 經典三欄工作台，支援登入頁「一鍵啟動本地服務」。
  - **Android 手機端**：抽屜側欄 ＋ 單欄切換、下拉更新與懸浮寫信按鈕。
  - **深色模式智慧適配**：自動反轉 HTML 郵件的白底黑字與淺灰邊框；遇到透明黑字圖片等特殊版面時，點擊右上角**「淺色信紙」**即可一鍵切換為白底閱讀。
- **原地保留排版免費翻譯**：整合 Edge / Google / MyMemory 多管道免費翻譯與後端快取，**直接在原郵件版面位置將標題與內文替換為譯文**（保留段落、粗體、超連結與按鈕），支援「檢視原文 / 檢視譯文」即時切換。
- **登入狀態新郵件系統彈窗提醒**：
  - **Windows**：原生 Win32 系統 Toast 通知，點擊即可喚醒視窗並開啟該郵件。
  - **Android**：高優先級通知欄 ＋ 頂部橫幅彈窗，同步顯示寄件者與自動標籤（如 `[驗證碼]`）。
- **自動分類規則與側欄標籤未讀提示**：
  - 支援一鍵匯入常用預設規則（驗證碼、帳單發票、開發通知、訂單物流、安全告警、訂閱推廣）並對歷史郵件一鍵執行；側欄「標籤分類」即時顯示未讀數量膠囊。
- **常用伺服器位址記憶**：自動記住曾成功連線或登入過的後端網址，點擊標籤即可快速切換。
- **防亂碼與 Gmail 虛擬目錄自動去重**：自動傳送 RFC 2971 **IMAP ID**、內建 `GB18030 / GBK / GB2312 / Big5` 編碼解碼，並略過 Gmail 虛擬彙整資料夾（`All Mail` / `Important` / `Starred`），跨副本連動已讀狀態。
- **內建 Web 管理後台（`/admin`）**：系統概覽、用戶與公開註冊開關管理、全站同步監控與一鍵下載資料庫備份。

---

## 新手快速上手（三種使用方式）

### 方式 A：單台 Windows 電腦本機使用（最簡單）

1. 確認 `mailcontrol_app.exe` 與 `mailcontrol-server.exe` 位於同一資料夾，開啟 `mailcontrol_app.exe`。
2. 在登入畫面點擊 **「一键启动本地服务（一鍵啟動本地服務）」**，系統會自動啟動 `http://127.0.0.1:8080` 並將本機資料庫儲存於 `%LOCALAPPDATA%\MailControl\local_data`。
3. 切換到 **「註冊帳號」** 建立本機帳號登入後，點擊左側 **「+」** 即可新增你的各類電子信箱。

> ⚠️ **新手提醒**：本機服務（`127.0.0.1:8080`）的資料庫與雲端主機彼此獨立。若要連線雲端資料請填入雲端網址；切換為本機服務時需先註冊一組本機帳號。

---

### 方式 B：電腦為主機 ＋ 手機區網同步（免租伺服器）

1. 在電腦啟動 `mailcontrol-server.exe`（或於電腦版點擊一鍵啟動本地服務），並確認 Windows 防火牆允許 TCP `8080` 連入。
2. 於電腦執行 `ipconfig` 查詢區網 IPv4 位址（例如 `192.168.1.100`）。
3. 手機安裝 `app-release.apk` 後，在登入頁右上角「伺服器」填入 `http://192.168.1.100:8080` 測試連線，並使用與電腦相同的帳號登入。

---

### 方式 C：部署至個人雲端 VPS ＋ 網域 HTTPS（隨時隨地 24 小時同步）

若你擁有 Linux VPS（`amd64` 或 `arm64`）與網域（以 `mail.example.com` 為例）：

1. **交叉編譯 Linux 執行檔**（於 `backend/` 目錄執行）：
   ```powershell
   $env:GOOS="linux"
   $env:GOARCH="amd64"   # 若為 ARM64 主機請改為 arm64
   go build -o mailcontrol-server ./cmd/server
   ```
2. **設定 `systemd` 常駐服務**（`/etc/systemd/system/mailcontrol.service`）：
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
3. **搭配 Caddy 設定自動 HTTPS 反向代理**：
   ```caddyfile
   mail.example.com {
       reverse_proxy 127.0.0.1:18080 {
           flush_interval -1
       }
   }
   ```
   > 加上 `flush_interval -1` 可確保 SSE 即時推播不被緩衝延遲。

---

## 主流信箱應用程式密碼 / 授權碼取得步驟

| 信箱類型 | IMAP / SMTP 設定 | 取得方式 |
| :--- | :--- | :--- |
| **Gmail** | `imap.gmail.com:993` (SSL)<br>`smtp.gmail.com:465` (SSL) | Google 帳號安全性 → 開啟 **兩步驟驗證** → 搜尋 **應用程式密碼（App Passwords）** → 建立一組名稱並複製 **16 位密碼**（去除空白）。 |
| **Outlook / Hotmail** | `outlook.office365.com:993` (SSL)<br>`smtp.office365.com:587` (STARTTLS) | Outlook 網頁版設定 → 郵件 → 同步電子郵件 → 開啟 IMAP；若有雙重驗證，於 Microsoft 帳號安全性建立應用程式密碼。 |
| **iCloud** | `imap.mail.me.com:993` (SSL)<br>`smtp.mail.me.com:587` (STARTTLS) | 登入 [account.apple.com](https://account.apple.com) →「登入與安全性」→ 產生「App 專用密碼」。 |
| **QQ / Foxmail** | `imap.qq.com:993` (SSL)<br>`smtp.qq.com:465` (SSL) | 網頁版設定 → 帳號 → 開啟 **IMAP/SMTP 服務** 並產生 **16 位授權碼**。 |
| **網易 163 / 126** | `imap.163.com:993` (SSL)<br>`smtp.163.com:465` (SSL) | 網頁版設定 → POP3/SMTP/IMAP → 開啟服務並產生授權密碼（系統已自動傳送 IMAP ID）。 |

---

## 常見操作說明與排錯（FAQ）

- **什麼是「簽名模板」？**：寄信時自動附加在內文末端的個人落款/名片，可針對不同信箱綁定不同簽名或設定通用預設簽名，寫信時也能隨時手動插入（不用可留空）。
- **如何進入管理後台（`/admin`）？**：瀏覽器開啟 `http://127.0.0.1:8080/admin` 或 `https://mail.example.com/admin`。**第一位註冊的帳號自動成為管理員**，可管理同步狀態、關閉公開註冊與下載資料庫備份。
- **收不到通知怎麼辦？**：Windows 請確認系統通知開啟且未啟用勿擾模式；Android 13+ 請於首次登入時允許通知權限並關閉省電限制。

---

## 伺服器環境變數與從原始碼建置

| 變數名稱 | 預設值 | 說明 |
| :--- | :--- | :--- |
| `HOST` | `0.0.0.0` | 監聽位址（搭配反代建議設為 `127.0.0.1`） |
| `PORT` | `8080` | 服務埠號 |
| `DATA_DIR` | `./data` | SQLite 資料庫、附件與金鑰儲存路徑 |
| `JWT_SECRET` | 自動產生 | JWT 簽章密鑰 |
| `ENC_KEY` | 自動產生 | 信箱密碼 AES-256-GCM 加密主金鑰 |
| `DEFAULT_SYNC_INTERVAL` | `180` | 預設背景同步間隔（秒，最小 `30`） |

建置測試指令：

```powershell
# 1. 執行單元測試
cd backend && go test ./...
cd ..\app && flutter analyze && flutter test

# 2. 一鍵建置 Windows (.exe) 與 Android (.apk)
powershell -ExecutionPolicy Bypass -File .\scripts\build-all.ps1
```
