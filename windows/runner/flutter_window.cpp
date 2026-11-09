#include "flutter_window.h"

#include <optional>
#include <dwmapi.h>
#include <flutter/standard_method_codec.h>
#include <cstring>
#include "instance_ipc.h"

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  // Ask Windows 11 for native rounding; older versions safely ignore this.
  // DWM keeps maximized/fullscreen and snapped windows under system policy.
  constexpr DWORD kRoundCorners = 2;  // DWMWCP_ROUND
  DwmSetWindowAttribute(GetHandle(), static_cast<DWMWINDOWATTRIBUTE>(33),
                        &kRoundCorners, sizeof(kRoundCorners));

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  file_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "io.github.julio_viera.VisorMarkdown/desktop_file_open",
      &flutter::StandardMethodCodec::GetInstance());
  file_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "getInitialRequests") { result->NotImplemented(); return; }
    flutter::EncodableList requests;
    for (auto& request : pending_requests_) requests.push_back(std::move(request));
    pending_requests_.clear();
    dart_ready_ = true;
    result->Success(flutter::EncodableValue(requests));
  });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  file_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_COPYDATA) {
    const auto* data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
    if (data == nullptr || data->dwData != instance_ipc::kOpenFilesTag ||
        data->lpData == nullptr || data->cbData == 0 || data->cbData > instance_ipc::kMaxPayload) return FALSE;
    const auto* bytes = static_cast<const char*>(data->lpData);
    if (bytes[data->cbData - 1] != '\0') return FALSE;
    flutter::EncodableList paths;
    size_t offset = 0;
    while (offset < data->cbData - 1) {
      const auto* end = static_cast<const char*>(std::memchr(bytes + offset, 0, data->cbData - offset));
      if (end == nullptr || end == bytes + offset) return FALSE;
      paths.emplace_back(std::string(bytes + offset, end));
      offset = static_cast<size_t>(end - bytes) + 1;
    }
    flutter::EncodableValue request(flutter::EncodableMap{
      {flutter::EncodableValue("paths"), flutter::EncodableValue(paths)}});
    if (dart_ready_ && file_channel_) {
      file_channel_->InvokeMethod("openRequest", std::make_unique<flutter::EncodableValue>(request));
    } else {
      pending_requests_.push_back(std::move(request));
    }
    if (::IsIconic(hwnd)) ::ShowWindow(hwnd, SW_RESTORE);
    ::SetForegroundWindow(hwnd);
    return TRUE;
  }

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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
