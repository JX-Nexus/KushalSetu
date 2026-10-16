import 'package:flutter/material.dart';

/// Warm, trustworthy palette: deep teal + saffron on warm off-white.
class AppTheme {
  static const Color primary = Color(0xFF0D7377);
  static const Color primaryDark = Color(0xFF094F52);
  static const Color primarySoft = Color(0xFFDDEFEF);
  static const Color accent = Color(0xFFE07A3D);
  static const Color accentSoft = Color(0xFFFCEBDD);
  static const Color background = Color(0xFFF7F4EE);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF1B2527);
  static const Color inkSoft = Color(0xFF5B6769);
  static const Color line = Color(0xFFE3DED3);
  static const Color success = Color(0xFF2E7D32);
  static const Color successSoft = Color(0xFFE3F1E4);
  static const Color warning = Color(0xFFB26A00);
  static const Color warningSoft = Color(0xFFFFF1D6);
  static const Color danger = Color(0xFFC62828);
  static const Color dangerSoft = Color(0xFFFBE4E4);
  static const Color info = Color(0xFF1565C0);
  static const Color infoSoft = Color(0xFFE3EEFB);

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
        backgroundColor: primary,
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
