import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'agent_config.dart';

class AgentLauncher {
  /// Launches ia-agent without popping a console window. `uv`/`python` are
  /// console-subsystem executables, so a plain Process.start from this GUI
  /// app would otherwise flash a terminal (CREATE_NO_WINDOW isn't exposed by
  /// dart:io, only by the raw Win32 CreateProcess call).
  static bool start() {
    final commandLine = 'uv run ia-agent'.toNativeUtf16();
    final currentDirectory = AgentConfig.agentDir.toNativeUtf16();
    final startupInfo = calloc<STARTUPINFO>()..ref.cb = sizeOf<STARTUPINFO>();
    final processInfo = calloc<PROCESS_INFORMATION>();

    try {
      final result = CreateProcess(
        null,
        PWSTR(commandLine),
        null,
        null,
        false,
        CREATE_NO_WINDOW,
        null,
        PCWSTR(currentDirectory),
        startupInfo,
        processInfo,
      );

      if (result.value) {
        CloseHandle(processInfo.ref.hProcess);
        CloseHandle(processInfo.ref.hThread);
      }

      return result.value;
    } finally {
      calloc.free(commandLine);
      calloc.free(currentDirectory);
      calloc.free(startupInfo);
      calloc.free(processInfo);
    }
  }
}
