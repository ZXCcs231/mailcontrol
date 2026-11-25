import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'core/theme.dart';
import 'providers/mail_provider.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'widgets/window_title_bar.dart';

void _setupWindowsWindow() {
  if (!Platform.isWindows) return;
  try {
    final win = WindowManager.instance.getCurrent();
    if (win != null) {
      win.title = 'MailControl';
      win.titleBarStyle = TitleBarStyle.hidden;
      win.isWindowControlButtonsVisible = false;
      win.minimumSize = const Size(900, 620).toNative();
      win.setSize(const Size(1240, 780).toNative(), false);
      win.show();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _setupWindowsWindow());
    }
  } catch (_) {}
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _setupWindowsWindow();
  runApp(const ProviderScope(child: MailControlApp()));
}

class MailControlApp extends ConsumerWidget {
  const MailControlApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return MaterialApp(
      title: 'MailControl 邮箱管理',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: auth.themeMode,
      builder: (context, child) {
        if (!Platform.isWindows) return child ?? const SizedBox.shrink();
        return Column(
          children: [
            const WindowTitleBar(),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        );
      },
      home: !auth.initialized
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : (auth.isAuthenticated ? const HomeScreen() : const AuthScreen()),
    );
  }
}
