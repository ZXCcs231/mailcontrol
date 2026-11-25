import 'dart:io';

import 'package:path/path.dart' as p;

class LocalServerManager {
  Process? _process;

  bool get isSupported => Platform.isWindows;
  bool get isRunningByUs => _process != null;

  String? findServerExecutable() {
    if (!Platform.isWindows) return null;

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = <String>[
      p.join(exeDir, 'mailcontrol-server.exe'),
      p.join(Directory.current.path, 'mailcontrol-server.exe'),
      p.join(Directory.current.path, 'backend', 'mailcontrol-server.exe'),
      p.join(Directory.current.parent.path, 'backend', 'mailcontrol-server.exe'),
    ];

    // 从可执行文件目录向上最多查找 6 层，兼容从 app/build/... 调试运行
    var cursor = Directory(exeDir);
    for (var i = 0; i < 6; i++) {
      candidates.add(p.join(cursor.path, 'backend', 'mailcontrol-server.exe'));
      final parent = cursor.parent;
      if (parent.path == cursor.path) break;
      cursor = parent;
    }

    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  Future<bool> startIfNeeded() async {
    if (!Platform.isWindows) return false;
    final exe = findServerExecutable();
    if (exe == null) return false;

    final workDir = File(exe).parent.path;
    _process = await Process.start(
      exe,
      const [],
      workingDirectory: workDir,
      mode: ProcessStartMode.detachedWithStdio,
    );
    await Future.delayed(const Duration(milliseconds: 900));
    return true;
  }

  void stop() {
    _process?.kill();
    _process = null;
  }
}
