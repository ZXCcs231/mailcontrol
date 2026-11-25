import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';

class MailControlLogo extends StatelessWidget {
  final double size;

  const MailControlLogo({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.mail_rounded,
            color: Colors.white,
            size: size * 0.56,
          ),
          Positioned(
            right: size * 0.14,
            bottom: size * 0.14,
            child: Container(
              width: size * 0.30,
              height: size * 0.30,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Icon(
                Icons.check_rounded,
                size: size * 0.19,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProviderBadge extends StatelessWidget {
  final String providerId;
  final Color fallbackColor;
  final double size;

  const ProviderBadge({
    super.key,
    required this.providerId,
    required this.fallbackColor,
    this.size = 24,
  });

  ({String label, Color bg, Color fg}) _style() {
    return switch (providerId) {
      'qq' => (label: 'QQ', bg: const Color(0xFFDBEAFE), fg: const Color(0xFF1D4ED8)),
      '163' => (label: '163', bg: const Color(0xFFFEE2E2), fg: const Color(0xFFDC2626)),
      '126' => (label: '126', bg: const Color(0xFFFCE7F3), fg: const Color(0xFFBE185D)),
      'gmail' => (label: 'G', bg: const Color(0xFFFEE2E2), fg: const Color(0xFFEA4335)),
      'outlook' => (label: 'O', bg: const Color(0xFFE0F2FE), fg: const Color(0xFF0284C7)),
      'icloud' => (label: 'iC', bg: const Color(0xFFE0E7FF), fg: const Color(0xFF4338CA)),
      'tencent_exmail' => (label: '企', bg: const Color(0xFFDBEAFE), fg: const Color(0xFF1E40AF)),
      'aliyun_qiye' => (label: '阿', bg: const Color(0xFFFFEDD5), fg: const Color(0xFFEA580C)),
      'feishu' => (label: '飞', bg: const Color(0xFFCCFBF1), fg: const Color(0xFF0F766E)),
      'sina' => (label: '新', bg: const Color(0xFFFEF3C7), fg: const Color(0xFFD97706)),
      'yahoo' => (label: 'Y', bg: const Color(0xFFF3E8FF), fg: const Color(0xFF7E22CE)),
      _ => (label: '邮', bg: fallbackColor.withValues(alpha: 0.14), fg: fallbackColor),
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = _style();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(size * 0.30),
        border: Border.all(color: s.fg.withValues(alpha: 0.22), width: 1),
      ),
      child: Text(
        s.label,
        style: TextStyle(
          color: s.fg,
          fontSize: s.label.length >= 3 ? size * 0.36 : (s.label.length == 2 ? size * 0.42 : size * 0.48),
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }
}

class SenderAvatar extends StatelessWidget {
  final String name;
  final double size;

  const SenderAvatar({super.key, required this.name, this.size = 38});

  static const _tones = [
    (bg: Color(0xFFEFF6FF), fg: Color(0xFF1D4ED8)),
    (bg: Color(0xFFECFDF5), fg: Color(0xFF047857)),
    (bg: Color(0xFFFEF2F2), fg: Color(0xFFB91C1C)),
    (bg: Color(0xFFFFFBEB), fg: Color(0xFFB45309)),
    (bg: Color(0xFFF5F3FF), fg: Color(0xFF6D28D9)),
    (bg: Color(0xFFECFEFF), fg: Color(0xFF0E7490)),
    (bg: Color(0xFFFDF2F8), fg: Color(0xFFBE185D)),
    (bg: Color(0xFFEEF2FF), fg: Color(0xFF4338CA)),
  ];

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isNotEmpty ? trimmed.substring(0, 1).toUpperCase() : '?';
    final hash = trimmed.codeUnits.fold<int>(0, (acc, c) => acc * 31 + c);
    final tone = _tones[hash.abs() % _tones.length];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark ? tone.fg.withValues(alpha: 0.22) : tone.bg,
        shape: BoxShape.circle,
        border: Border.all(
          color: tone.fg.withValues(alpha: isDark ? 0.35 : 0.16),
          width: 1,
        ),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: isDark ? Colors.white.withValues(alpha: 0.92) : tone.fg,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }
}

class HoverSurface extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovering) builder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;

  const HoverSurface({
    super.key,
    required this.builder,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
  });

  @override
  State<HoverSurface> createState() => _HoverSurfaceState();
}

class _HoverSurfaceState extends State<HoverSurface> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: widget.builder(context, _hovering),
      ),
    );
  }
}

/// 圆角美化的统一下拉选择表单框，避免默认直角弹出卡片显得生硬。
class AppDropdownField<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final String? Function(T?)? validator;

  const AppDropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.decoration = const InputDecoration(isDense: true),
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      validator: validator,
      isExpanded: true,
      menuMaxHeight: 320,
      elevation: 6,
      dropdownColor: pal.surfaceElevated,
      borderRadius: BorderRadius.circular(14),
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: pal.textPrimary,
      ),
      icon: Icon(
        Icons.keyboard_arrow_down_rounded,
        size: 20,
        color: pal.textSecondary,
      ),
      decoration: decoration.copyWith(
        border: decoration.border ??
            OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: pal.borderSubtle),
            ),
        enabledBorder: decoration.enabledBorder ??
            OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: pal.borderSubtle),
            ),
        focusedBorder: decoration.focusedBorder ??
            OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: pal.accent, width: 1.5),
            ),
      ),
    );
  }
}
