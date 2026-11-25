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

  String _resolveDataDir(String exePath) {
    final exeDir = File(exePath).parent.path;
    final localDb = File(p.join(exeDir, 'data', 'mailcontrol.db'));
    if (localDb.existsSync()) {
      return p.join(exeDir, 'data');
    }
    final appData = Platform.environment['LOCALAPPDATA'];
    if (appData != null && appData.isNotEmpty) {
      final dir = Directory(p.join(appData, 'MailControl', 'local_data'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir.path;
    }
    return p.join(exeDir, 'data');
  }

  Future<bool> startIfNeeded() async {
    if (!Platform.isWindows) return false;
    final exe = findServerExecutable();
    if (exe == null) return false;

    final workDir = File(exe).parent.path;
    final dataDir = _resolveDataDir(exe);
    _process = await Process.start(
      exe,
      const [],
      workingDirectory: workDir,
      environment: {'DATA_DIR': dataDir},
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
