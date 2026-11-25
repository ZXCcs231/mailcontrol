$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
  throw "未检测到 go 命令，请先安装 Go 并将其加入系统 PATH。"
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw "未检测到 flutter 命令，请先安装 Flutter SDK 并将其加入系统 PATH。"
}

Write-Host "==> 1. 编译 Go 后端服务..." -ForegroundColor Cyan
Push-Location (Join-Path $Root "backend")
go build -o mailcontrol-server.exe ./cmd/server
Pop-Location

Write-Host "==> 2. 编译 Flutter Windows 桌面端..." -ForegroundColor Cyan
Push-Location (Join-Path $Root "app")
flutter build windows --release
$winReleaseDir = Join-Path $Root "app\build\windows\x64\runner\Release"
if (Test-Path $winReleaseDir) {
  Copy-Item -Force (Join-Path $Root "backend\mailcontrol-server.exe") (Join-Path $winReleaseDir "mailcontrol-server.exe")
  Write-Host "Windows 客户端与内置后端已输出至: $winReleaseDir" -ForegroundColor Green
}

Write-Host "==> 3. 编译 Flutter Android APK..." -ForegroundColor Cyan
flutter build apk --release
Pop-Location

Write-Host "全部构建完成！" -ForegroundColor Green
