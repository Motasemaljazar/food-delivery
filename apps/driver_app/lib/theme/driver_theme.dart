import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ثيم تطبيق السائق — أحمر مثل تطبيق الزبون + خط Cairo
class DriverTheme {
  static const Color primaryRed = Color(0xFFC41E3A);
  static const Color primaryRedDark = Color(0xFFD32F2F);

  static TextTheme get cairoTextTheme =>
      GoogleFonts.cairoTextTheme(ThemeData.light().textTheme);

  static TextTheme get cairoTextThemeDark =>
      GoogleFonts.cairoTextTheme(ThemeData.dark().textTheme);

  static ThemeData lightTheme(Color? primaryOverride) {
    final primary = primaryOverride ?? primaryRed;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      primary: primary,
      surface: Colors.white,
      onSurface: const Color(0xFF1A1A1A),
      onSurfaceVariant: const Color(0xFF616161),
      outline: const Color(0xFFE0E0E0),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: cairoTextTheme,
      fontFamily: 'Cairo',
      scaffoldBackgroundColor: const Color(0xFFF8F8F8),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.cairo(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF1A1A1A),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1A1A1A), size: 24),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
    );
  }

  static ThemeData darkTheme(Color? primaryOverride) {
    final primary = primaryOverride ?? primaryRed;
    const surfaceDark = Color(0xFF1C1C1C);
    const surfaceContainer = Color(0xFF252525);
    const onSurfaceDark = Color(0xFFE8E8E8);
    const onSurfaceVariantDark = Color(0xFFB0B0B0);
    const outlineDark = Color(0xFF3D3D3D);

    final colorScheme = ColorScheme.dark(
      primary: primary,
      onPrimary: Colors.white,
      surface: surfaceDark,
      onSurface: onSurfaceDark,
      onSurfaceVariant: onSurfaceVariantDark,
      outline: outlineDark,
      surfaceContainerHighest: surfaceContainer,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      textTheme: cairoTextThemeDark.apply(
        bodyColor: onSurfaceDark,
        displayColor: onSurfaceDark,
      ),
      fontFamily: 'Cairo',
      scaffoldBackgroundColor: const Color(0xFF121212),
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceContainer,
        foregroundColor: onSurfaceDark,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.cairo(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: onSurfaceDark,
        ),
        iconTheme: const IconThemeData(color: onSurfaceDark, size: 24),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceDark,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: outlineDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: const TextStyle(color: onSurfaceVariantDark),
        hintStyle: const TextStyle(color: onSurfaceVariantDark),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      dividerColor: outlineDark,
    );
  }
}
