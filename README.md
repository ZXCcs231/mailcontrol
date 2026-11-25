# MailControl — 跨端多账号主流邮箱统一管理系统

**MailControl** 是一套完全原生的跨平台多邮箱统一管理系统（无 Web 浏览器套壳），采用 **Go 统一后端 + Flutter 原生客户端（Windows 桌面端 `.exe` + Android 手机端 `.apk`）** 架构。只需一个系统账号，即可同时绑定并管理所有主流邮箱（QQ / Foxmail、网易 163/126、Gmail、Outlook / Hotmail、iCloud、腾讯/阿里/飞书企业邮、新浪、Yahoo 及自定义 IMAP/SMTP）。

---

## 核心特性

1. **单账号管理多个不同邮箱**：自由绑定多个不同服务商邮箱，自定义名称与标识色，支持连接测试与 AES-256-GCM 凭证加密存储。
2. **双端原生自适应体验**：
   - **Windows 桌面端**：经典三栏工作台布局（左侧导航/邮箱树 + 中间邮件列表 + 右侧安全正文阅读），支持登录页一键拉起本地后端服务。
   - **Android 手机端**：抽屉侧栏 + 单栏列表/详情流畅切换、下拉刷新同步与悬浮写信按钮，连接电脑或服务器后端即可与桌面端实时同步所有邮箱、标签、规则与签名。
3. **内置 12 种主流邮箱一键预设与国内兼容优化**：
   - 输入邮箱后缀自动识别服务器配置并附带授权码获取指南。
   - 自动针对网易 163/126 发送 RFC 2971 **IMAP ID**，避免 `Unsafe Login`。
   - 内置 `GB18030 / GBK / GB2312 / Big5` 等字符集解码，解决中文老旧邮件乱码。
4. **完整收发与高效管理**：
   - 统一收件箱、星标、已发送、草稿箱、归档、回收站；按单个邮箱或远端文件夹筛选。
   - 写信、回复、回复全部、转发、多附件上传与下载打开、全字段搜索、未读/附件筛选、批量操作。
5. **自动化与实时推送**：
   - 后台按账号独立间隔增量同步，通过 SSE 实时推送新邮件提醒。
   - 可视化**自动分类规则引擎**（支持新邮件自动触发及对历史邮件立即运行）、**彩色标签体系**与**多签名模板**。

---

## 本机开发环境路径

- **Go**：`D:\environment\go`（`GOPATH=D:\environment\go-path`，`GOPROXY=https://goproxy.cn,direct`）
- **Flutter SDK**：`D:\environment\flutter`（`PUB_CACHE=D:\environment\pub-cache`）
- **Android SDK**：`D:\environment\Android\Sdk`

---

## 快速启动与使用指南

### 1. 运行 Go 后端单元测试与服务

```powershell
cd e:\code\mailcontrol\backend
go test -v ./...
go build -o mailcontrol-server.exe ./cmd/server
.\mailcontrol-server.exe
```

后端默认监听 `0.0.0.0:8080`，数据（SQLite 数据库、附件及本地自动生成的密钥 `secrets.json`）保存在 `backend\data\`。

### 2. 运行或打包客户端

- **一键构建全平台产物**：
  ```powershell
  powershell -ExecutionPolicy Bypass -File e:\code\mailcontrol\scripts\build-all.ps1
  ```
- **直接调试运行 Windows 端**：
  ```powershell
  cd e:\code\mailcontrol\app
  flutter run -d windows
  ```
- **编译 Android APK**：
  ```powershell
  cd e:\code\mailcontrol\app
  flutter build apk --release
  ```
  > 提示：若在 Windows 上首次编译含插件的桌面端，请确保已在 **Windows 设置 → 系统 → 开发者选项** 中开启“开发人员模式”（用于创建 Flutter 插件所需的符号链接）。

### 3. 手机端与 Windows 端局域网同步教程

1. 在电脑运行 `mailcontrol-server.exe`（或 Windows 客户端中点击“一键启动本地服务”），确保 Windows 防火墙允许 `8080` 端口入站通信。
2. 在电脑执行 `ipconfig` 查看局域网 IP（例如 `192.168.1.100`）。
3. 手机安装 APK 后，在登录界面右上角点击 **服务器图标**，填入 `http://192.168.1.100:8080` 并点击“测试连接”。
4. 使用同一套 MailControl 账号登录，手机端与 Windows 端即可同步全部已绑定邮箱、邮件、标签、自动规则与签名。

---

## 主流邮箱授权码配置提示

| 邮箱类型 | IMAP / SMTP 服务器 | 注意事项 |
| :--- | :--- | :--- |
| **QQ / Foxmail** | `imap.qq.com:993` / `smtp.qq.com:465` (SSL) | 网页版设置 → 账号 → 开启 IMAP/SMTP 并生成 16 位授权码 |
| **网易 163 / 126** | `imap.163.com:993` / `smtp.163.com:465` (SSL) | 开启 IMAP 并生成授权密码；后端已自动发送 IMAP ID |
| **Gmail** | `imap.gmail.com:993` / `smtp.gmail.com:465` (SSL) | 需开启两步验证并生成 Google 应用专用密码 |
| **Outlook / Hotmail** | `outlook.office365.com:993` / `smtp.office365.com:587` (STARTTLS) | 在设置中开启 IMAP 访问 |
| **iCloud** | `imap.mail.me.com:993` / `smtp.mail.me.com:587` (STARTTLS) | 在 `account.apple.com` 生成 App 专用密码 |

---

## 目录结构

```text
mailcontrol/
├── backend/          # Go 统一后端服务（Gin + SQLite + IMAP/SMTP + 规则引擎 + SSE）
├── app/              # Flutter 原生客户端（Windows 桌面端 + Android 手机端）
├── scripts/          # 一键编译打包脚本
└── README.md
```
