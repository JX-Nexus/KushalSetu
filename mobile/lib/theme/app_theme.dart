import 'package:flutter/material.dart';

/// KaushalSetu design system: deep navy + blue, fresh green accent, warm neutral background.
/// Spacing scale: 4 / 8 / 12 / 16 / 20 / 24. Corner radii: 12 (fields), 16 (cards), 24 (hero).
class AppTheme {
  static const Color primary = Color(0xFF1A4FA3);
  static const Color primaryDark = Color(0xFF0B2A5B);
  static const Color primarySoft = Color(0xFFE6EEFB);
  static const Color accent = Color(0xFF178A4B);
  static const Color accentSoft = Color(0xFFE3F5EA);
  static const Color background = Color(0xFFF6F4EF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF14213D);
  static const Color inkSoft = Color(0xFF5C677D);
  static const Color line = Color(0xFFE4E0D6);
  static const Color success = Color(0xFF1E8E4E);
  static const Color successSoft = Color(0xFFE3F5EA);
  static const Color warning = Color(0xFFB45309);
  static const Color warningSoft = Color(0xFFFEF3C7);
  static const Color danger = Color(0xFFC0392B);
  static const Color dangerSoft = Color(0xFFFDE8E6);
  static const Color info = Color(0xFF1A4FA3);
  static const Color infoSoft = Color(0xFFE6EEFB);

  // Vivid accents (used for illustration-led screens and colour-coded sections).
  static const Color saffron = Color(0xFFE8590C);
  static const Color saffronDeep = Color(0xFFC2410C);
  static const Color saffronSoft = Color(0xFFFFEDDF);
  static const Color sun = Color(0xFFFFC53D);
  static const Color teal = Color(0xFF0E9AA7);
  static const Color tealSoft = Color(0xFFDDF4F6);
  static const Color plum = Color(0xFF7048E8);
  static const Color plumSoft = Color(0xFFECE6FD);
  static const Color navyLight = Color(0xFF123F8C);

  /// Section colour cycle: [strong, soft]
  static const List<List<Color>> sectionColors = [
    [saffronDeep, saffronSoft],
    [teal, tealSoft],
    [plum, plumSoft],
    [primary, primarySoft],
  ];

  static const Color navy = primaryDark;
  static const Color mint = accentSoft;
  static const double rCard = 16;
  static const double rHero = 28;

  static Color scoreColor(int s) {
    switch (s) {
      case 3:
        return success;
      case 2:
        return const Color(0xFF558B2F);
      case 1:
        return warning;
      default:
        return danger;
    }
  }

  /// Consistent text-field look without depending on ThemeData's input theme type.
  static InputDecoration field({
    String? labelText,
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? errorText,
    bool isDense = false,
  }) {
    OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      errorText: errorText,
      isDense: isDense,
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(line, 1),
      enabledBorder: border(line, 1),
      focusedBorder: border(primary, 2),
    );
  }

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: accent,
      error: danger,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          foregroundColor: primary,
          side: const BorderSide(color: primary, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
