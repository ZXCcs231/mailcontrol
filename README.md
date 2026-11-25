<div align="center">

# 📬 MailControl

**完全原生、开源自托管的跨端多账号邮箱统一管理系统**

[![Go](https://img.shields.io/badge/Backend-Go%201.26%20%2B%20Gin%20%2B%20SQLite-00ADD8?style=flat-square&logo=go)](backend/)
[![Flutter](https://img.shields.io/badge/Client-Flutter%20Native%20(Windows%20%2B%20Android)-02569B?style=flat-square&logo=flutter)](app/)
[![Protocol](https://img.shields.io/badge/Protocol-IMAP%20%2B%20SMTP%20%2B%20SSE-10B981?style=flat-square)](#核心功能一览)

**简体中文** | [English](README.en.md) | [日本語](README.ja.md) | [繁體中文](README.zh-TW.md)

</div>

---

## 一分钟看懂 MailControl

平时你可能同时有 QQ 邮箱、网易 163、Gmail、学校邮箱或公司邮箱——每次查验证码或找账单都要在好几个 App / 网页之间来回切换，甚至手机和电脑各自绑定一遍、配置一遍。

**MailControl** 用**“一个后端 + 双端原生客户端”**帮你彻底简化这件事：

```text
  +--------------------+          HTTPS / 局域网 HTTP          +-----------------------------+
  |  Windows 桌面端    |  <--------------------------------->  |      MailControl 后端        |
  |  (mailcontrol_app) |       JWT 登录 + REST API + SSE       |   (Go + SQLite + IMAP/SMTP) |
  +--------------------+                                       +-----------------------------+
                                                                              ^
  +--------------------+                                                      |
  |   Android 手机端   |  <---------------------------------------------------+
  | (app-release.apk)  |     同一账号登录，邮箱/邮件/标签/规则/签名全自动同步
  +--------------------+
```

- **不是网页套壳**：Windows 桌面端（`.exe`）和 Android 手机端（`.apk`）均基于 Flutter 原生编译，启动快、响应顺滑。
- **一次绑定，多端共用**：只要登录同一个 MailControl 账号，无论你在电脑还是手机上，所有已绑定邮箱、未读状态、彩色标签、自动规则、签名模板**全部自动实时同步**。
- **数据完全掌握在自己手里**：服务端是一个单文件 Go 程序 + SQLite 数据库，既可以在自己电脑上一键拉起，也可以部署在自己的轻量云服务器上 24 小时后台收信。

---

## 核心功能一览

- **一个账号管所有主流邮箱**：内置 **12 类主流邮箱一键预设**（QQ / Foxmail、网易 163 / 126、Gmail、Outlook / Hotmail、iCloud、腾讯/阿里/飞书企业邮、新浪、Yahoo 及自定义 IMAP/SMTP），输入邮箱地址自动匹配服务器配置，授权密码使用 **AES-256-GCM** 加密保存。
- **原生态双端界面 & 无缝深色模式**：
  - **Windows 桌面端**：无边框融合标题栏 + 三栏工作台（左侧邮箱/标签导航 + 中间邮件列表 + 右侧正文阅读），支持登录页「一键启动本地服务」。
  - **Android 手机端**：抽屉侧栏 + 单栏列表/详情流畅切换、下拉刷新与悬浮写信。
  - **深色模式正文自适应**：自动反转邮件内嵌的白底黑字与浅灰边框，读信不刺眼；遇到带透明黑字图片等特殊排版时，点击详情页右上角**「浅色信纸」**即可一键还原白底。
- **原地保排版免费翻译**：内置 Edge / Google / MyMemory 多渠道免费翻译（无需配置付费 Key），**直接在原邮件排版位置将标题和正文替换为译文**（保留段落、加粗、超链接与按钮），支持一键切换「查看原文 / 查看译文」与服务端缓存。
- **登录态新邮件系统弹窗提醒**：
  - **Windows**：通过 Win32 原生通知弹出桌面 Toast 提醒，点击可直接置顶窗口并打开对应邮件。
  - **Android**：高优先级通知栏 + 顶部横幅弹窗（Heads-up），并展示所属邮箱与自动分类标签（如 `[验证码]`）。
  - 退出登录后自动停止推送，历史旧未读不会重复刷屏弹窗。
- **自动化分类引擎与彩色标签提醒**：
  - 可视化配置**自动分类规则**（支持一键导入「验证码」「账单发票」「开发通知」「订单物流」「安全告警」「订阅推广」等常用预设，支持对历史邮件一键重跑）。
  - 左侧栏「标签分类」实时展示各分类未读数字胶囊，不错过验证码与重要通知。
- **常用服务器地址记忆**：登录页自动记录成功连接/登录过的后端地址，点击标签一键切换。
- **针对国内与 Gmail 的专项优化**：
  - 自动发送 RFC 2971 **IMAP ID**，解决网易 163/126 `Unsafe Login` 拦截。
  - 内置 `GB18030 / GBK / GB2312 / Big5` 字符集解码，告别老旧中文邮件乱码。
  - 自动过滤 Gmail 的 `[Gmail]/所有邮件`、`[Gmail]/重要`、`[Gmail]/已加星标` 虚拟聚合目录，杜绝重复邮件与已读计数不同步。
- **内置 Web 管理后台（`/admin`）**：系统概览、用户与公开注册开关管理、全站邮箱同步监控、一键导出 SQLite 数据库备份。

---

## 小白快速上手（三种使用方式任选）

### 方式 A：只在一台 Windows 电脑上单机使用（最简单）

适合只想在本地管理多个邮箱、不需要手机同步的用户，**3 步即可开始**：

1. 解压 Windows 发行目录，确认目录内同时包含 `mailcontrol_app.exe` 和 `mailcontrol-server.exe`，双击打开 `mailcontrol_app.exe`。
2. 在登录页点击 **「一键启动本地服务」**（程序会自动拉起本地后端 `http://127.0.0.1:8080`，并把本地数据库持久化保存在 `%LOCALAPPDATA%\MailControl\local_data`）。
3. 切换到 **「注册账号」** 创建一个本地登录账号并登录，然后点击左侧 **「+」** 添加你的 QQ / 163 / Gmail 等邮箱即可开始收发。

> ⚠️ **新手注意**：本地服务（`127.0.0.1:8080`）的数据库与云端服务器互相独立。如果你以前在云端注册过账号，切换回本地服务时需要先在本地注册一个账号（不能直接用云端账号密码登录本地库）。

---

### 方式 B：电脑作为主机 + 手机端局域网同步（零服务器成本）

适合家里/宿舍/办公室电脑与手机连在**同一个 Wi-Fi / 路由器**下使用：

1. **在电脑端启动后端**：打开电脑客户端点击「一键启动本地服务」，或者单独双击运行 `mailcontrol-server.exe`。
2. **放行防火墙端口**：确保 Windows 防火墙允许 `8080` 端口的 TCP 入站连接（或允许 `mailcontrol-server.exe` 联网）。
3. **查看电脑局域网 IP**：在电脑上按 `Win + R` 输入 `cmd` 回车，运行 `ipconfig`，找到当前 Wi-Fi/以太网的 **IPv4 地址**（例如 `192.168.1.100`）。
4. **手机端连接**：
   - 在手机安装 `app-release.apk`。
   - 打开登录页右上角 **「服务器」**，输入 `http://192.168.1.100:8080`（替换为你电脑的实际 IP），点击 **「测试连接」**。
   - 提示连接正常后，使用与电脑端相同的 MailControl 账号登录，两边就会同步全部邮箱和邮件。

---

### 方式 C：部署到自己的云服务器（推荐：手机随时随地 24 小时同步）

如果你有一台 Linux 云服务器（`amd64` 或 `arm64` 均可）和自己的域名（下文以 `mail.example.com` 举例）：

1. **交叉编译 Linux 单文件服务端**（在开发电脑的 `backend/` 目录运行）：
   ```powershell
   # 如果是 x86_64 服务器，使用 GOARCH=amd64；如果是 ARM64 服务器（如 Oracle Ampere），使用 GOARCH=arm64
   $env:GOOS="linux"
   $env:GOARCH="amd64"
   go build -o mailcontrol-server ./cmd/server
   ```
2. **上传并配置 `systemd` 后台常驻运行**（示例 `/etc/systemd/system/mailcontrol.service`）：
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
3. **配置 HTTPS 反向代理（以 Caddy 为例，自动申请 SSL 证书）**：
   ```caddyfile
   mail.example.com {
       reverse_proxy 127.0.0.1:18080 {
           flush_interval -1
       }
   }
   ```
   > 提示：`flush_interval -1` 可确保 SSE 新邮件实时推送连接不被反代缓冲卡住。
4. **客户端连接**：在 Windows 与 Android 登录页的后端服务地址中填入 `https://mail.example.com`，连接一次后系统会自动记入「常用地址」方便日后切换。

---

## 主流邮箱授权码获取指南

> 💡 几乎所有国内主流邮箱和开启了两步验证的国外邮箱，**在第三方客户端登录时不能直接填网页登录密码**，必须填写专门生成的**「授权码 / 应用专用密码」**。

| 邮箱类型 | 收件 / 发件服务器（自动填充） | 小白获取授权码步骤 |
| :--- | :--- | :--- |
| **QQ / Foxmail** | `imap.qq.com:993` (SSL)<br>`smtp.qq.com:465` (SSL) | 登录网页版 QQ 邮箱 → 右上角「设置」→「账号」→ 向下找到 **POP3/IMAP/SMTP/Exchange/CardDAV/CalDAV 服务** → 开启 **IMAP/SMTP 服务** → 按短信验证生成 **16 位授权码**。 |
| **网易 163 / 126** | `imap.163.com:993` (SSL)<br>`smtp.163.com:465` (SSL) | 登录网页版网易邮箱 → 顶部「设置」→「POP3/SMTP/IMAP」→ 开启 **IMAP/SMTP 服务** → 点击「新增授权密码」，复制保存生成的授权密码（系统已内置 IMAP ID 自动通过网易安全检查）。 |
| **Gmail** | `imap.gmail.com:993` (SSL)<br>`smtp.gmail.com:465` (SSL) | 打开 Google 账号安全设置 → 开启 **两步验证（2-Step Verification）** → 在安全设置中搜索 **应用专用密码（App Passwords）** → 新建一个名称（如 `MailControl`），复制生成的 **16 位密码**（去掉空格）。 |
| **Outlook / Hotmail** | `outlook.office365.com:993` (SSL)<br>`smtp.office365.com:587` (STARTTLS) | 登录网页版 Outlook → 右上角齿轮「设置」→「邮件」→「同步电子邮件」→ 确认允许设备和应用使用 POP/IMAP；若开启了双重验证，请在微软账号安全中心生成应用专用密码。 |
| **iCloud** | `imap.mail.me.com:993` (SSL)<br>`smtp.mail.me.com:587` (STARTTLS) | 登录 [account.apple.com](https://account.apple.com) →「登录和安全」→「App 专用密码」→ 点击生成并复制粘贴到客户端密码框。 |

---

## 日常高频功能说明

### 1. 什么是「签名模板」？
「签名模板」就是你写邮件时自动附在正文末尾的**个人落款/名片**（例如姓名、单位、联系方式、祝语）。
- 可以在左下角 **「签名模板」** 中创建多套签名，分别绑定到不同邮箱（如学校邮箱绑定中文学术签名、Gmail 绑定英文签名），也可以设为「通用签名（所有邮箱）」。
- 新建写邮件时会自动带入对应发件邮箱的默认签名；写信或回复过程中也可以点击工具栏上的签名按钮随时插入切换。不创建任何模板则不会附加签名。

### 2. 自动分类规则与标签角标
- 点击左下角 **「自动规则」** → **「导入常用预设」**，可一键导入常用规则，并可点击规则卡片上的运行按钮对已有历史邮件执行分类。
- 新邮件到达时会自动按规则打上彩色标签，并在左侧栏「标签分类」中展示未读数量角标，同时在系统弹窗通知上标出所属标签。

### 3. 原地翻译邮件
- 在阅读邮件工具栏点击 **翻译图标（文A）** 选择目标语言，译文会**直接替换原邮件排版中的文字原地渲染**（保留超链接、按钮、加粗等格式），并在标题下方提供一键「查看原文 / 查看译文」切换。

### 4. Web 管理后台（`/admin`）
- 用浏览器打开你的服务端地址加 `/admin`（例如 `http://127.0.0.1:8080/admin` 或 `https://mail.example.com/admin`）。
- **首位注册的用户自动成为管理员**，可使用管理员账号密码登录后台，查看全站邮箱同步状态、关闭/开启新用户公开注册、重置普通用户密码或直接下载数据库备份文件。
- 如果服务端开启了新部署环境，建议在团队/个人账号注册完成后，在后台关闭「允许公开注册」。

---

## 小白常见排错（FAQ）

<details>
<summary><b>Q1：点击「一键启动本地服务」后，为什么输入原来的账号密码提示“账号或密码错误”？</b></summary>

因为本地服务使用的是本机 `%LOCALAPPDATA%\MailControl\local_data` 下的独立 SQLite 数据库，与你的云端服务器数据库完全隔离。如果是第一次用本地服务，请先点击「注册账号」创建本地账号；若要访问云端邮箱数据，请将后端地址切换为你的云端服务地址（不要点启动本地服务）。
</details>

<details>
<summary><b>Q2：添加邮箱时测试连接失败，提示认证错误或 Unsafe Login？</b></summary>

1. 请确认密码框填的是网页邮箱后台生成的**授权码 / 应用专用密码**，而不是邮箱网页登录密码。
2. 网易 163/126 请确认已在网页端打开 IMAP/SMTP 服务；Gmail 与 iCloud 请确认已开启两步验证并生成 16 位专用密码。
3. 云端部署在海外服务器上登录 QQ/163 时，若被邮箱风控拦截，可登录网页版查看是否有异地登录/安全确认提示。
</details>

<details>
<summary><b>Q3：手机端连接电脑局域网地址时一直转圈或提示无法连接？</b></summary>

1. 确认手机和电脑连接在**同一个路由器 Wi-Fi** 下（勿使用手机 4G/5G 流量或开启会拦截局域网的代理）。
2. 检查电脑端是否确实启动了 `mailcontrol-server.exe`。
3. 检查 Windows Defender 防火墙是否拦截了 `8080` 端口入站（可在“高级安全 Windows Defender 防火墙”添加 TCP `8080` 入站允许规则，或将当前网络设为“专用网络”）。
</details>

<details>
<summary><b>Q4：收到新邮件没有看到系统弹窗提示？</b></summary>

- **Windows**：检查 Windows 系统设置 → 系统 → 通知，确认通知总开关已开启且未打开「请勿打扰」。
- **Android**：Android 13 及以上系统首次登录后会弹出通知权限请求，请点击「允许」；若之前误点拒绝，可在手机系统「应用信息 → MailControl → 通知权限」中手动打开，并关闭省电策略限制以便后台保持推送连接。
</details>

<details>
<summary><b>Q5：深色模式下个别带图片/Logo 的邮件文字颜色看着别扭怎么办？</b></summary>

MailControl 已内置深色模式色彩智能反转适配；若遇到把文字直接做成透明黑字 PNG 图片的邮件，只需点击该邮件标题右上角的 **「浅色信纸」**，即可临时以白底信纸完整还原原貌。
</details>

---

## 服务端环境变量配置

生产环境可通过环境变量覆盖默认配置（未设置 `JWT_SECRET` / `ENC_KEY` 时，程序首次启动会自动生成并持久化保存在 `DATA_DIR/secrets.json`）：

| 变量名 | 默认值 | 说明 |
| :--- | :--- | :--- |
| `HOST` | `0.0.0.0` | 监听地址（若配合 Caddy/Nginx 反代建议设为 `127.0.0.1`） |
| `PORT` | `8080` | 服务监听端口 |
| `DATA_DIR` | `./data` | SQLite 数据库（`mailcontrol.db`）、附件目录与密钥文件存放路径 |
| `JWT_SECRET` | 自动生成 | 登录 JWT 签名密钥（建议生产环境固定设置） |
| `ENC_KEY` | 自动生成 | 邮箱授权码 AES-256-GCM 加密主密钥（请勿随意更改，否则已存邮箱密码需重新录入） |
| `DEFAULT_SYNC_INTERVAL` | `180` | 新绑定邮箱默认后台同步间隔（秒，最小 `30`） |

---

## 从源码编译与打包

### 环境准备
- **Go**：1.24+（仓库 `go.mod` 当前使用 Go 1.26，纯 Go 编译，无需 CGO/GCC）
- **Flutter SDK**：3.27+（开启 Windows Desktop 与 Android 工具链）
- **Windows 编译环境**：Visual Studio Build Tools / Visual Studio（勾选“使用 C++ 的桌面开发”），并在 **Windows 设置 → 系统 → 开发者选项** 中开启 **「开发人员模式」**（Flutter 插件创建符号链接需要此权限）。
- **Android 编译环境**：JDK 17+ 与 Android SDK。

### 常用命令（仓库根目录运行）

- **运行全部测试**：
  ```powershell
  # 后端单元测试
  cd backend
  go test ./...

  # 客户端静态检查与单元测试
  cd ..\app
  flutter analyze
  flutter test
  ```
- **一键构建 Windows `.exe`（含内置服务端）与 Android `.apk`**：
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\scripts\build-all.ps1
  ```
  构建产物位置：
  - Windows 客户端与内嵌服务端：`app\build\windows\x64\runner\Release\mailcontrol_app.exe`（同目录自动拷贝 `mailcontrol-server.exe`）
  - Android 安装包：`app\build\app\outputs\flutter-apk\app-release.apk`

---

## 目录结构

```text
mailcontrol/
├── backend/                  # Go 统一后端服务（Gin + SQLite + IMAP/SMTP + 规则引擎 + 多渠道翻译 + SSE + /admin）
├── app/                      # Flutter 原生跨端客户端（Windows 桌面端 + Android 手机端）
├── scripts/                  # 一键编译打包脚本（build-all.ps1）
├── README.md                 # 简体中文文档
├── README.en.md              # English Documentation
├── README.ja.md              # 日本語ドキュメント
└── README.zh-TW.md           # 繁體中文文件
```
