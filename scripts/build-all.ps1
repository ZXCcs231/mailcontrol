$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$env:GOROOT = "D:\environment\go"
$env:GOPATH = "D:\environment\go-path"
$env:GOPROXY = "https://goproxy.cn,direct"
$env:PUB_CACHE = "D:\environment\pub-cache"
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
$env:ANDROID_HOME = "D:\environment\Android\Sdk"
$env:Path = "D:\environment\go\bin;D:\environment\go-path\bin;D:\environment\flutter\bin;" + $env:Path

Write-Host "==> 1. 编译 Go 后端服务..." -ForegroundColor Cyan
Push-Location "$Root\backend"
go build -o mailcontrol-server.exe ./cmd/server
Pop-Location

Write-Host "==> 2. 编译 Flutter Windows 桌面端..." -ForegroundColor Cyan
Push-Location "$Root\app"
flutter build windows --release
$winReleaseDir = "$Root\app\build\windows\x64\runner\Release"
if (Test-Path $winReleaseDir) {
  Copy-Item -Force "$Root\backend\mailcontrol-server.exe" "$winReleaseDir\mailcontrol-server.exe"
  Write-Host "Windows 客户端与内置后端已输出至: $winReleaseDir" -ForegroundColor Green
}

Write-Host "==> 3. 编译 Flutter Android APK..." -ForegroundColor Cyan
flutter build apk --release
Pop-Location

Write-Host "全部构建完成！" -ForegroundColor Green
