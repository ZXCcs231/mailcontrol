#include "flutter_window.h"

#include <cwchar>
#include <optional>
#include <variant>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kTrayIconCallbackMessage = WM_APP + 101;
constexpr UINT kTrayIconId = 1001;

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) {
    return L"";
  }
  const int required = MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  if (required <= 0) {
    return L"";
  }
  std::wstring out(static_cast<size_t>(required), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      out.data(), required);
  return out;
}

void CopyWideTruncated(wchar_t* dest, size_t dest_count,
                       const std::wstring& src) {
  if (dest_count == 0) {
    return;
  }
  const size_t max_chars = dest_count - 1;
  const size_t copy_len = src.size() < max_chars ? src.size() : max_chars;
  if (copy_len > 0) {
    wmemcpy(dest, src.data(), copy_len);
  }
  dest[copy_len] = L'\0';
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() { RemoveTrayIcon(); }

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetupNotificationChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::SetupNotificationChannel() {
  notification_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "mailcontrol/windows_notifications",
          &flutter::StandardMethodCodec::GetInstance());

  notification_channel_->SetMethodCallHandler(
      [this](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) {
        if (call.method_name() == "show") {
          std::string title;
          std::string body;
          std::string payload;
          if (const auto* args =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            if (auto it = args->find(flutter::EncodableValue("title"));
                it != args->end()) {
              if (const auto* s = std::get_if<std::string>(&it->second)) {
                title = *s;
              }
            }
            if (auto it = args->find(flutter::EncodableValue("body"));
                it != args->end()) {
              if (const auto* s = std::get_if<std::string>(&it->second)) {
                body = *s;
              }
            }
            if (auto it = args->find(flutter::EncodableValue("payload"));
                it != args->end()) {
              if (const auto* s = std::get_if<std::string>(&it->second)) {
                payload = *s;
              }
            }
          }
          ShowWindowsNotification(title, body, payload);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

void FlutterWindow::ShowWindowsNotification(const std::string& title,
                                            const std::string& body,
                                            const std::string& payload) {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }

  if (!tray_icon_added_) {
    ZeroMemory(&tray_icon_data_, sizeof(tray_icon_data_));
    tray_icon_data_.cbSize = sizeof(NOTIFYICONDATAW);
    tray_icon_data_.hWnd = hwnd;
    tray_icon_data_.uID = kTrayIconId;
    tray_icon_data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    tray_icon_data_.uCallbackMessage = kTrayIconCallbackMessage;
    tray_icon_data_.hIcon =
        LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
    if (!tray_icon_data_.hIcon) {
      tray_icon_data_.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
    }
    CopyWideTruncated(tray_icon_data_.szTip,
                      sizeof(tray_icon_data_.szTip) / sizeof(wchar_t),
                      L"MailControl");

    if (Shell_NotifyIconW(NIM_ADD, &tray_icon_data_)) {
      tray_icon_data_.uVersion = NOTIFYICON_VERSION_4;
      Shell_NotifyIconW(NIM_SETVERSION, &tray_icon_data_);
      tray_icon_added_ = true;
    } else {
      return;
    }
  }

  last_notification_payload_ = payload;
  tray_icon_data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_INFO;
  tray_icon_data_.dwInfoFlags = NIIF_INFO;
  CopyWideTruncated(tray_icon_data_.szInfoTitle,
                    sizeof(tray_icon_data_.szInfoTitle) / sizeof(wchar_t),
                    Utf8ToWide(title));
  CopyWideTruncated(tray_icon_data_.szInfo,
                    sizeof(tray_icon_data_.szInfo) / sizeof(wchar_t),
                    Utf8ToWide(body));
  Shell_NotifyIconW(NIM_MODIFY, &tray_icon_data_);
}

void FlutterWindow::RemoveTrayIcon() {
  if (tray_icon_added_) {
    Shell_NotifyIconW(NIM_DELETE, &tray_icon_data_);
    tray_icon_added_ = false;
  }
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  notification_channel_.reset();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case kTrayIconCallbackMessage: {
      const UINT event = LOWORD(lparam);
      if (event == NIN_BALLOONUSERCLICK || event == NIN_SELECT ||
          event == WM_LBUTTONDBLCLK) {
        if (IsIconic(hwnd)) {
          ShowWindow(hwnd, SW_RESTORE);
        }
        ShowWindow(hwnd, SW_SHOW);
        SetForegroundWindow(hwnd);
        if (event == NIN_BALLOONUSERCLICK && notification_channel_) {
          notification_channel_->InvokeMethod(
              "onTap",
              std::make_unique<flutter::EncodableValue>(
                  last_notification_payload_));
        }
      }
      break;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
