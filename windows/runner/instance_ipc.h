#ifndef RUNNER_INSTANCE_IPC_H_
#define RUNNER_INSTANCE_IPC_H_

#include <windows.h>
namespace instance_ipc {
inline constexpr wchar_t kWindowClass[] = L"io.github.julio_viera.VisorMarkdown.Window";
inline constexpr wchar_t kMutexName[] = L"Local\\io.github.julio_viera.VisorMarkdown.Instance";
inline constexpr ULONG_PTR kOpenFilesTag = 0x564d444f;
inline constexpr DWORD kMaxPayload = 1024 * 1024;
}
#endif
