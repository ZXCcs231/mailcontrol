import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../core/theme.dart';
import 'brand_widgets.dart';

class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) return const SizedBox.shrink();
    final pal = context.palette;

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: pal.sidebarBg,
        border: Border(bottom: BorderSide(color: pal.borderSubtle, width: 1)),
      ),
      child: WindowCaption(
        brightness: Theme.of(context).brightness,
        backgroundColor: Colors.transparent,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MailControlLogo(size: 18),
            const SizedBox(width: 8),
            Text(
              'MailControl',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: pal.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
