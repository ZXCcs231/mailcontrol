import 'dart:io';

import 'package:material_ui/material_ui.dart';

class AppPalette extends ThemeExtension<AppPalette> {
  final Color sidebarBg;
  final Color listBg;
  final Color readingBg;
  final Color surfaceElevated;
  final Color hoverBg;
  final Color activeBg;
  final Color borderSubtle;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color accentSoft;

  const AppPalette({
    required this.sidebarBg,
    required this.listBg,
    required this.readingBg,
    required this.surfaceElevated,
    required this.hoverBg,
    required this.activeBg,
    required this.borderSubtle,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentSoft,
  });

  static const light = AppPalette(
    sidebarBg: Color(0xFFF3F5F9),
    listBg: Color(0xFFFFFFFF),
    readingBg: Color(0xFFF8FAFC),
    surfaceElevated: Color(0xFFFFFFFF),
    hoverBg: Color(0xFFEEF2F7),
    activeBg: Color(0xFFE7EFFD),
    borderSubtle: Color(0xFFE5EAF1),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF64748B),
    accent: Color(0xFF2563EB),
    accentSoft: Color(0xFFEFF6FF),
  );

  static const dark = AppPalette(
    sidebarBg: Color(0xFF0F1624),
    listBg: Color(0xFF111827),
    readingBg: Color(0xFF0B1120),
    surfaceElevated: Color(0xFF182234),
    hoverBg: Color(0xFF1E293B),
    activeBg: Color(0xFF1E3A5F),
    borderSubtle: Color(0xFF243044),
    textPrimary: Color(0xFFF1F5F9),
    textSecondary: Color(0xFFCBD5E1),
    textMuted: Color(0xFF94A3B8),
    accent: Color(0xFF60A5FA),
    accentSoft: Color(0xFF172554),
  );

  @override
  AppPalette copyWith({
    Color? sidebarBg,
    Color? listBg,
    Color? readingBg,
    Color? surfaceElevated,
    Color? hoverBg,
    Color? activeBg,
    Color? borderSubtle,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? accentSoft,
  }) =>
      AppPalette(
        sidebarBg: sidebarBg ?? this.sidebarBg,
        listBg: listBg ?? this.listBg,
        readingBg: readingBg ?? this.readingBg,
        surfaceElevated: surfaceElevated ?? this.surfaceElevated,
        hoverBg: hoverBg ?? this.hoverBg,
        activeBg: activeBg ?? this.activeBg,
        borderSubtle: borderSubtle ?? this.borderSubtle,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textMuted: textMuted ?? this.textMuted,
        accent: accent ?? this.accent,
        accentSoft: accentSoft ?? this.accentSoft,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      sidebarBg: Color.lerp(sidebarBg, other.sidebarBg, t)!,
      listBg: Color.lerp(listBg, other.listBg, t)!,
      readingBg: Color.lerp(readingBg, other.readingBg, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      hoverBg: Color.lerp(hoverBg, other.hoverBg, t)!,
      activeBg: Color.lerp(activeBg, other.activeBg, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
    );
  }
}

extension AppPaletteX on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}

class AppTheme {
  static const Color primarySeed = Color(0xFF2563EB);

  static String? get fontFamily => Platform.isWindows ? 'Microsoft YaHei UI' : null;
  static const List<String> fontFallback = [
    'Microsoft YaHei UI',
    'Segoe UI',
    'PingFang SC',
    'Noto Sans SC',
    'sans-serif',
  ];

  static TextTheme _buildTextTheme(TextTheme base, AppPalette p) {
    return base
        .copyWith(
          headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3, color: p.textPrimary),
          titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2, color: p.textPrimary),
          titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: p.textPrimary),
          bodyLarge: base.bodyLarge?.copyWith(fontSize: 14.5, height: 1.55, color: p.textPrimary),
          bodyMedium: base.bodyMedium?.copyWith(fontSize: 13.5, height: 1.45, color: p.textPrimary),
          bodySmall: base.bodySmall?.copyWith(fontSize: 12, height: 1.4, color: p.textSecondary),
          labelMedium: base.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: p.textSecondary),
        )
        .apply(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallback,
        );
  }

  static ThemeData light() {
    const p = AppPalette.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: primarySeed,
      brightness: Brightness.light,
    ).copyWith(
      primary: p.accent,
      surface: p.surfaceElevated,
      outlineVariant: p.borderSubtle,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
    );
    return base.copyWith(
      scaffoldBackgroundColor: p.readingBg,
      extensions: const [p],
      textTheme: _buildTextTheme(base.textTheme, p),
      appBarTheme: AppBarTheme(
        backgroundColor: p.listBg,
        foregroundColor: p.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.borderSubtle),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: TextStyle(fontFamily: fontFamily, fontFamilyFallback: fontFallback, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          side: BorderSide(color: p.borderSubtle),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.readingBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.borderSubtle, thickness: 1, space: 1),
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: WidgetStateProperty.all(false),
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(6),
      ),
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: p.accent.withValues(alpha: 0.18),
        cursorColor: p.accent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: p.borderSubtle),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.borderSubtle),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStateProperty.all(p.surfaceElevated),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          elevation: WidgetStateProperty.all(6),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: p.borderSubtle),
            ),
          ),
        ),
      ),
    );
  }

  static ThemeData dark() {
    const p = AppPalette.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: p.accent,
      surface: p.surfaceElevated,
      outlineVariant: p.borderSubtle,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
    );
    return base.copyWith(
      scaffoldBackgroundColor: p.readingBg,
      extensions: const [p],
      textTheme: _buildTextTheme(base.textTheme, p),
      appBarTheme: AppBarTheme(
        backgroundColor: p.listBg,
        foregroundColor: p.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.borderSubtle),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: TextStyle(fontFamily: fontFamily, fontFamilyFallback: fontFallback, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: p.borderSubtle),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.readingBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.borderSubtle, thickness: 1, space: 1),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(6),
      ),
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: p.accent.withValues(alpha: 0.25),
        cursorColor: p.accent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: p.borderSubtle),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.borderSubtle),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStateProperty.all(p.surfaceElevated),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          elevation: WidgetStateProperty.all(6),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: p.borderSubtle),
            ),
          ),
        ),
      ),
    );
  }
}

Color parseHexColor(String hex, {Color fallback = const Color(0xFF2563EB)}) {
  final cleaned = hex.replaceAll('#', '').trim();
  if (cleaned.length == 6) {
    final v = int.tryParse('FF$cleaned', radix: 16);
    if (v != null) return Color(v);
  } else if (cleaned.length == 8) {
    final v = int.tryParse(cleaned, radix: 16);
    if (v != null) return Color(v);
  }
  return fallback;
}
