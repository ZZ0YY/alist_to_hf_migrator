#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <iostream>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  ::HWND window = ::FindWindow(L"FlutterViewWindow", nullptr);
  if (window != nullptr) {
    ::SetForegroundWindow(window);
    return EXIT_FAILURE;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_command_line_arguments(command_line_arguments);

  FlutterWindow window_obj(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);

  if (!window_obj.Create(L"Alist to HF Migrator", origin, size)) {
    return EXIT_FAILURE;
  }

  window_obj.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  return EXIT_SUCCESS;
}
