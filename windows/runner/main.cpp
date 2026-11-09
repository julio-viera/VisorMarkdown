#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <cstdint>
#include "instance_ipc.h"

#include "flutter_window.h"
#include "utils.h"

namespace {
struct InstanceGuard {
  HANDLE handle;
  bool owns;
  ~InstanceGuard() {
    if (owns) ::ReleaseMutex(handle);
    if (handle != nullptr) ::CloseHandle(handle);
  }
};
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  InstanceGuard guard{::CreateMutexW(nullptr, TRUE, instance_ipc::kMutexName), false};
  const bool already_running = ::GetLastError() == ERROR_ALREADY_EXISTS;
  if (guard.handle == nullptr) return EXIT_FAILURE;
  guard.owns = !already_running;
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  if (already_running) {
    for (int attempt = 0; attempt < 100; ++attempt) {
      const DWORD status = ::WaitForSingleObject(guard.handle, 0);
      if (status == WAIT_ABANDONED || status == WAIT_OBJECT_0) {
        guard.owns = true;  // The previous process exited before accepting work.
        break;
      }
      HWND existing = ::FindWindowW(instance_ipc::kWindowClass, nullptr);
      if (existing != nullptr) {
        std::vector<uint8_t> bytes;
        for (const auto& path : command_line_arguments) {
          bytes.insert(bytes.end(), path.begin(), path.end());
          bytes.push_back(0);
        }
        bytes.push_back(0);
        if (bytes.size() > instance_ipc::kMaxPayload) return EXIT_FAILURE;
        COPYDATASTRUCT data{instance_ipc::kOpenFilesTag,
          static_cast<DWORD>(bytes.size()), bytes.data()};
        DWORD pid = 0;
        ::GetWindowThreadProcessId(existing, &pid);
        ::AllowSetForegroundWindow(pid);
        DWORD_PTR accepted = FALSE;
        const auto sent = ::SendMessageTimeoutW(existing, WM_COPYDATA, 0,
          reinterpret_cast<LPARAM>(&data), SMTO_ABORTIFHUNG | SMTO_BLOCK, 5000, &accepted);
        if (sent != 0 && accepted != FALSE) return EXIT_SUCCESS;
        ::MessageBoxW(nullptr, L"No se pudo enviar la apertura a la ventana existente. Inténtalo de nuevo.",
                      L"Visor Markdown", MB_OK | MB_ICONWARNING);
        return EXIT_FAILURE;
      }
      ::Sleep(50);
    }
    if (!guard.owns) return EXIT_FAILURE;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Visor Markdown", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
