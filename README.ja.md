<div align="center">

# 📬 MailControl

**完全ネイティブ・オープンソース・セルフホスト対応 マルチアカウントメール統合管理システム**

[![Go](https://img.shields.io/badge/Backend-Go%201.26%20%2B%20Gin%20%2B%20SQLite-00ADD8?style=flat-square&logo=go)](backend/)
[![Flutter](https://img.shields.io/badge/Client-Flutter%20Native%20(Windows%20%2B%20Android)-02569B?style=flat-square&logo=flutter)](app/)
[![Protocol](https://img.shields.io/badge/Protocol-IMAP%20%2B%20SMTP%20%2B%20SSE-10B981?style=flat-square)](#主な機能)

[简体中文](README.md) | [English](README.en.md) | **日本語** | [繁體中文](README.zh-TW.md)

</div>

---

## 1分でわかる MailControl

Gmail、Outlook、iCloud、大学・仕事用メール、QQ / 163 メールなど複数のアドレスを使い分けていると、認証コードや請求書を確認するたびにアプリを行き来したり、PC とスマホで同じ設定を繰り返したりしがちです。

**MailControl** は **「単一の Go バックエンド ＋ Windows / Android ネイティブアプリ」** でメール環境を一元化します：

```text
  +--------------------+        HTTPS / LAN HTTP        +------------------------------+
  |  Windows デスクトップ |  <-------------------------->  |      MailControl サーバー     |
  | (mailcontrol_app)  |    JWT + REST API + SSE 通知    |  (Go + SQLite + IMAP/SMTP)   |
  +--------------------+                                +------------------------------+
                                                                        ^
  +--------------------+                                                |
  |   Android スマホ   |  <---------------------------------------------+
  | (app-release.apk)  |  同一アカウントでログイン -> メール・タグ・ルール・署名を自動同期
  +--------------------+
```

- **Web ブラウザラッパー不使用**：Windows（`.exe`）と Android（`.apk`）の両方が Flutter でネイティブコンパイルされており、高速に動作します。
- **一度登録すれば全端末で共有**：PC でもスマホでも同じ MailControl アカウントでログインするだけで、登録済みメールボックス、未読状態、カラータグ、自動分類ルール、署名テンプレートがリアルタイムで同期されます。
- **データは完全に手元で管理**：単一バイナリの Go サーバーと SQLite データベースで構成されており、PC でワンクリック起動することも、自分の VPS で 24 時間運用することも可能です。

---

## 主な機能

- **12 種類の主要メールサービスプリセット**：Gmail、Outlook / Hotmail、iCloud、Yahoo、QQ / Foxmail、NetEase 163 / 126、企業向けメール、カスタム IMAP/SMTP に対応。パスワードは **AES-256-GCM** で暗号化して保存されます。
- **ネイティブ UI ＆ スマートダークモード**：
  - **Windows 版**：フレームレス統合タイトルバー ＋ 3 ペインワークスペース ＋ ログイン画面から「ローカルサーバーをワンクリック起動」。
  - **Android 版**：ドロワーナビゲーション ＋ 画面サイズに応じたリスト／詳細表示 ＋ 引っ張って更新。
  - **ダークモード自動最適化**：HTML メールの白い背景や濃い文字色を暗い画面向けに自動調整。透過黒文字 PNG ロゴ等で見づらいメールは右上の**「ライト用紙（浅色信纸）」**ボタンでワンクリック白背景切替が可能。
- **レイアウト保持の無料インプレース翻訳**：Edge / Google / MyMemory の無料翻訳を自動フォールバックで利用し、**元の HTML 構造（リンク・太字・ボタン・段落）を保ったまま本文と件名を直接翻訳表示**します。ワンクリックで「原文表示 / 翻訳表示」を切り替え可能です。
- **ログイン中のシステム通知ポップアップ**：
  - **Windows**：Win32 ネイティブトースト通知を表示し、クリックでウィンドウを前面表示して該当メールを開きます。
  - **Android**：高優先度バナー通知を表示し、受信メールボックスや自動付与されたタグ（例：`[認証コード]`）も表示します。
- **自動分類ルール ＆ タグ別未読バッジ**：
  - プリセットルール（認証コード、請求書、開発通知、配送、セキュリティ警告、プロモーション）をワンクリックで導入でき、過去のメールにも一括適用可能。
  - サイドバーの「タグ分類」にリアルタイムの未読件数バッジを表示します。
- **接続先サーバー履歴**：接続やログインに成功したバックエンド URL を自動記憶し、ワンクリックで切り替えられます。
- **Gmail 仮想フォルダ重複排除 ＆ 日本語・中国語レガシー文字コード対応**：
  - Gmail の `[Gmail]/すべて`・`重要`・`スター付き` などの仮想フォルダを重複同期せず、既読状態やスターを同一アカウントのコピー間で同期します。
  - NetEase 向け RFC 2971 **IMAP ID** 自動送信や `GB18030 / GBK / Big5` デコードにも対応。
- **Web 管理画面（`/admin`）**：稼働状況、各アカウントの同期監視、新規公開登録の ON/OFF 切替、ユーザー管理、SQLite データベースバックアップダウンロードが可能。

---

## 初心者向けクイックスタート（3通りの使い方）

### 方法 A：Windows PC 1 台でローカル完結（最も簡単）

サーバー契約やドメインは不要、**3 ステップ**で始められます：

1. `mailcontrol_app.exe` と `mailcontrol-server.exe` を同じフォルダに置き、`mailcontrol_app.exe` を起動します。
2. ログイン画面で **「一键启动本地服务（ローカルサーバー起動）」** をクリックします（`http://127.0.0.1:8080` が起動し、データは `%LOCALAPPDATA%\MailControl\local_data` に保存されます）。
3. **「登録」** タブでローカル用アカウントを作成してログインし、左側の **「+」** からお持ちのメールアカウントを登録します。

> ⚠️ **ご注意**：ローカルサーバー（`127.0.0.1:8080`）とクラウドサーバーは別のデータベースを使用します。クラウド版で作成したアカウントはローカル DB には存在しないため、ローカル利用時は最初にローカルアカウントを新規登録してください。

---

### 方法 B：PC を親機にしてスマホと Wi-Fi（LAN）同期

1. **PC 側でサーバーを起動**：Windows アプリからローカルサーバーを起動するか、`mailcontrol-server.exe` を直接実行します。
2. **Windows ファイアウォールで `8080` ポートを許可**：TCP 受信 `8080` を許可します。
3. **PC のローカル IP を確認**：コマンドプロンプト等で `ipconfig` を実行し、IPv4 アドレス（例：`192.168.1.100`）を確認します。
4. **Android から接続**：`app-release.apk` をインストールし、ログイン画面右上の **サーバーボタン** に `http://192.168.1.100:8080` を入力して接続テスト後、PC と同じアカウントでログインします。

---

### 方法 C：クラウド VPS ＋ 独自ドメイン HTTPS で 24 時間同期

Linux VPS（`amd64` または `arm64`）とドメイン（例：`mail.example.com`）をお持ちの場合：

1. **Linux 用バイナリをクロスビルド**（`backend/` ディレクトリで実行）：
   ```powershell
   # x86_64 サーバーは amd64、ARM64 サーバーは arm64 を指定
   $env:GOOS="linux"
   $env:GOARCH="amd64"
   go build -o mailcontrol-server ./cmd/server
   ```
2. **`systemd` で常駐起動**（`/etc/systemd/system/mailcontrol.service`）：
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
3. **Caddy リバースプロキシ（自動 HTTPS）**：
   ```caddyfile
   mail.example.com {
       reverse_proxy 127.0.0.1:18080 {
           flush_interval -1
       }
   }
   ```
   > `flush_interval -1` を指定することで、SSE によるリアルタイム新着通知が遅延なく届きます。
4. **クライアント接続**：Windows と Android の接続先に `https://mail.example.com` を入力してください。

---

## 各メールサービスのアプリパスワード取得方法

> 多くのメールサービスでは、外部アプリ連携時に通常のログインパスワードではなく専用の**「アプリパスワード / 認証コード」**が必要です。

| サービス | IMAP / SMTP（自動入力） | 取得手順 |
| :--- | :--- | :--- |
| **Gmail** | `imap.gmail.com:993` (SSL)<br>`smtp.gmail.com:465` (SSL) | Google アカウント → **セキュリティ** → **2 段階認証プロセス**を有効化 → **アプリ パスワード** を検索して作成 → 表示された **16 桁のコード**（スペース除く）を入力。 |
| **Outlook / Hotmail** | `outlook.office365.com:993` (SSL)<br>`smtp.office365.com:587` (STARTTLS) | Web 版 Outlook の「設定」→「メール」→「メールの同期」で IMAP を有効化。2 段階認証有効時は Microsoft アカウントセキュリティ画面でアプリパスワードを発行。 |
| **iCloud** | `imap.mail.me.com:993` (SSL)<br>`smtp.mail.me.com:587` (STARTTLS) | [account.apple.com](https://account.apple.com) にサインイン →「サインインとセキュリティ」→「アプリ用パスワード」を生成して入力。 |
| **QQ / Foxmail** | `imap.qq.com:993` (SSL)<br>`smtp.qq.com:465` (SSL) | Web 版設定 →「アカウント」→ IMAP/SMTP サービスを有効化し、SMS 認証で **16 桁の認証コード** を取得。 |
| **NetEase 163 / 126** | `imap.163.com:993` (SSL)<br>`smtp.163.com:465` (SSL) | Web 版設定 →「POP3/SMTP/IMAP」→ IMAP/SMTP を有効化し認証パスワードを発行（IMAP ID はバックエンドが自動送信します）。 |

---

## 日常機能のポイント

- **署名テンプレート**：メール作成時に末尾へ自動挿入される署名です。アカウントごとの個別署名や共通のデフォルト署名を設定でき、作成画面から手動挿入も可能です（不要な場合は未設定のままで問題ありません）。
- **管理画面（`/admin`）**：`http://127.0.0.1:8080/admin` または `https://mail.example.com/admin` にアクセスします。**最初に登録されたユーザーが自動的に管理者権限**を持ち、同期監視・新規登録の停止・パスワードリセット・DB バックアップが可能です。

---

## よくある質問（FAQ）

<details>
<summary><b>Q1: ローカルサーバーを起動したら、クラウドのアカウントでログインできません。</b></summary>

ローカルサーバーは PC 内（`%LOCALAPPDATA%\MailControl\local_data`）の独立した SQLite DB を使用するため、クラウド DB とはアカウントが別管理です。ローカル利用時は「登録」から新規作成してください。
</details>

<details>
<summary><b>Q2: スマホから PC のローカルサーバーへ接続できません。</b></summary>

PC とスマホが同じ Wi-Fi に接続されているか、`mailcontrol-server.exe` が起動しているか、Windows ファイアウォールでポート `8080` の受信が許可されているかをご確認ください。
</details>

<details>
<summary><b>Q3: 新着メールのシステム通知が表示されません。</b></summary>

Windows では「通知」および「応答不可モード」の設定を、Android（13 以上）では初回ログイン時の通知権限許可（または端末のアプリ設定 → 通知権限）をご確認ください。
</details>

---

## サーバー環境変数

| 変数名 | デフォルト値 | 説明 |
| :--- | :--- | :--- |
| `HOST` | `0.0.0.0` | バインドアドレス（リバースプロキシ併用時は `127.0.0.1` 推奨） |
| `PORT` | `8080` | 待ち受けポート |
| `DATA_DIR` | `./data` | `mailcontrol.db`・添付ファイル・`secrets.json` の保存先 |
| `JWT_SECRET` | 自動生成 | JWT 署名キー（初回起動時に自動生成・保存） |
| `ENC_KEY` | 自動生成 | メールパスワードの AES-256-GCM 暗号化マスターキー |
| `DEFAULT_SYNC_INTERVAL` | `180` | バックグラウンド同期間隔のデフォルト値（秒、最小 `30`） |

---

## ソースからのビルド方法

- **動作要件**：Go 1.24+（Pure Go / CGO 不要）、Flutter 3.27+、JDK 17 + Android SDK、Visual Studio C++ デスクトップ開発ツール ＋ **Windows 開発者モード** 有効化。
- **テスト実行**：
  ```powershell
  cd backend && go test ./...
  cd ..\app && flutter analyze && flutter test
  ```
- **Windows ＋ Android 一括ビルド**：
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\scripts\build-all.ps1
  ```

---

## ディレクトリ構成

```text
mailcontrol/
├── backend/                  # Go バックエンド（Gin + SQLite + IMAP/SMTP + ルール + 翻訳 + SSE + /admin）
├── app/                      # Flutter ネイティブアプリ（Windows + Android）
├── scripts/                  # 一括ビルドスクリプト（build-all.ps1）
├── README.md                 # 簡体字中国語
├── README.en.md              # 英語
├── README.ja.md              # 日本語
└── README.zh-TW.md           # 繁体字中国語
```
