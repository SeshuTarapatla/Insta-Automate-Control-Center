import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

/// Where VS Code lives: the Electron binary plus the CLI entry point it needs
/// in order to act on a file rather than just start another editor process.
typedef _VsCode = ({String exe, String cli});

/// Opens files and Explorer windows without ever flashing a console window —
/// same constraint as [AgentLauncher] (DECISIONS D5).
class FileOpener {
  /// ShellExecute returns a value <= 32 to signal failure — a legacy HINSTANCE
  /// convention, not a real handle.
  static const _successThreshold = 32;

  /// Opens [path] for editing, preferring VS Code, then the shell association,
  /// then Notepad.
  ///
  /// Launching `Code.exe <file>` directly does **not** work: it starts a second
  /// Electron main process that exits without opening anything (the spawn still
  /// reports success, which is what made this look like a silent no-op). The
  /// `code` shim on PATH actually runs `Code.exe <cli.js> <file>` with
  /// `ELECTRON_RUN_AS_NODE=1`, and that CLI entry point is what hands the file
  /// to the running window. This replicates the shim rather than the binary.
  static Future<bool> openForEditing(String path) async {
    final vsCode = _resolveVsCode();
    if (vsCode != null) {
      try {
        await Process.start(
          vsCode.exe,
          [vsCode.cli, path],
          environment: {'ELECTRON_RUN_AS_NODE': '1'},
          mode: ProcessStartMode.detached,
        );
        return true;
      } on ProcessException catch (e) {
        debugPrint('[FileOpener] VS Code launch failed: $e');
      }
    }

    if (_shellExecute(operation: 'open', file: path)) return true;
    return _shellExecute(operation: 'open', file: 'notepad.exe', parameters: '"$path"');
  }

  /// Opens Explorer with [path] selected, rather than opening the file itself.
  static bool revealInExplorer(String path) =>
      _shellExecute(operation: 'open', file: 'explorer.exe', parameters: '/select,"$path"');

  /// Opens [url] in the default browser — same `ShellExecute(open, …)` call
  /// used for files, no new Win32 surface.
  static bool openUrl(String url) => _shellExecute(operation: 'open', file: url);

  /// Finds VS Code via the `code` shim on PATH.
  ///
  /// The shim itself is `code.cmd`, which cannot be spawned without a console
  /// flash, but it always sits in `<install>\bin`, which locates both the
  /// GUI-subsystem `Code.exe` and the `cli.js` beside it. Recent builds nest
  /// resources under a version-hash directory, so cli.js is searched for rather
  /// than assumed.
  static _VsCode? _resolveVsCode() {
    for (final entry in (Platform.environment['PATH'] ?? '').split(';')) {
      final dir = entry.trim();
      if (dir.isEmpty || !File('$dir\\code.cmd').existsSync()) continue;

      final install = Directory(dir).parent;
      final exe = File('${install.path}\\Code.exe');
      if (!exe.existsSync()) continue;

      final cli = _findCli(install);
      if (cli != null) return (exe: exe.path, cli: cli);
    }
    return null;
  }

  static String? _findCli(Directory install) {
    const suffix = 'resources\\app\\out\\cli.js';

    final classic = File('${install.path}\\$suffix');
    if (classic.existsSync()) return classic.path;

    for (final child in install.listSync().whereType<Directory>()) {
      final hashed = File('${child.path}\\$suffix');
      if (hashed.existsSync()) return hashed.path;
    }
    return null;
  }

  static bool _shellExecute({required String operation, required String file, String? parameters}) {
    final operationPtr = operation.toNativeUtf16();
    final filePtr = file.toNativeUtf16();
    final parametersPtr = parameters?.toNativeUtf16();

    try {
      final result = ShellExecute(
        null,
        PCWSTR(operationPtr),
        PCWSTR(filePtr),
        parametersPtr == null ? null : PCWSTR(parametersPtr),
        null,
        SW_SHOWNORMAL,
      );
      return result.address > _successThreshold;
    } finally {
      calloc.free(operationPtr);
      calloc.free(filePtr);
      if (parametersPtr != null) calloc.free(parametersPtr);
    }
  }
}
