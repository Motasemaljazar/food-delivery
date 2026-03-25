import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/app_state.dart';

class BrandSchemes {
  BrandSchemes({required this.light, required this.dark});
  final ColorScheme light;
  final ColorScheme dark;
}

class AppTheme {
  // ألوان صاحب المشروع: أحمر - أبيض - أصفر
  static const Color fallbackPrimary = Color(0xFFC41E3A);   // أحمر
  static const Color fallbackSecondary = Color(0xFFF9A825); // أصفر
  static const Color accentColor = Color(0xFFFFC107);       // أصفر فاتح
  static const Color errorColor = Color(0xFFB71C1C);         // أحمر للخطأ
  static const Color successColor = Color(0xFF2E7D32);       // أخضر للنجاح
  static const Color warningColor = Color(0xFFF9A825);       // أصفر للتحذير
  static const Color infoColor = Color(0xFF1565C0);         // أزرق للمعلومات

  // خلفيات
  static const Color cardBg = Colors.white;
  static const Color surfaceBg = Color(0xFFFAFAFA);
  static const Color scaffoldBg = Color(0xFFF8F8F8);

  // تدرجات أحمر - أصفر
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFC41E3A), Color(0xFFD32F2F)],
  );

  static const LinearGradient secondaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF9A825), Color(0xFFFFC107)],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFC107), Color(0xFFFFD54F)],
  );

  // Premium Shadows
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.04),
      offset: const Offset(0, 2),
      blurRadius: 8,
      spreadRadius: 0,
    ),
    BoxShadow(
      color: Colors.black.withOpacity(0.02),
      offset: const Offset(0, 4),
      blurRadius: 16,
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> get elevatedShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.08),
      offset: const Offset(0, 4),
      blurRadius: 12,
      spreadRadius: 0,
    ),
    BoxShadow(
      color: Colors.black.withOpacity(0.04),
      offset: const Offset(0, 8),
      blurRadius: 24,
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> get buttonShadow => [
    BoxShadow(
      color: fallbackPrimary.withOpacity(0.3),
      offset: const Offset(0, 4),
      blurRadius: 12,
      spreadRadius: 0,
    ),
  ];

  /// خط Cairo لكل التطبيق
  static TextTheme get arabicTextTheme {
    return TextTheme(
      displayLarge: GoogleFonts.cairo(
        fontWeight: FontWeight.w900,
        fontSize: 34,
        letterSpacing: -0.5,
        height: 1.2,
      ),
      displayMedium: GoogleFonts.cairo(
        fontWeight: FontWeight.w900,
        fontSize: 30,
        letterSpacing: -0.5,
        height: 1.2,
      ),
      displaySmall: GoogleFonts.cairo(
        fontWeight: FontWeight.w800,
        fontSize: 26,
        letterSpacing: -0.25,
        height: 1.2,
      ),
      headlineLarge: GoogleFonts.cairo(
        fontWeight: FontWeight.w800,
        fontSize: 30,
        height: 1.3,
      ),
      headlineMedium: GoogleFonts.cairo(
        fontWeight: FontWeight.w800,
        fontSize: 26,
        height: 1.3,
      ),
      headlineSmall: GoogleFonts.cairo(
        fontWeight: FontWeight.w700,
        fontSize: 22,
        height: 1.3,
      ),
      titleLarge: GoogleFonts.cairo(
        fontWeight: FontWeight.w700,
        fontSize: 20,
        height: 1.4,
        letterSpacing: 0.15,
      ),
      titleMedium: GoogleFonts.cairo(
        fontWeight: FontWeight.w600,
        fontSize: 18,
        height: 1.4,
        letterSpacing: 0.15,
      ),
      titleSmall: GoogleFonts.cairo(
        fontWeight: FontWeight.w600,
        fontSize: 16,
        height: 1.4,
        letterSpacing: 0.1,
      ),
      bodyLarge: GoogleFonts.cairo(
        fontWeight: FontWeight.w500,
        fontSize: 16,
        height: 1.6,
        letterSpacing: 0.5,
      ),
      bodyMedium: GoogleFonts.cairo(
        fontWeight: FontWeight.w400,
        fontSize: 14,
        height: 1.6,
        letterSpacing: 0.25,
      ),
      bodySmall: GoogleFonts.cairo(
        fontWeight: FontWeight.w400,
        fontSize: 12,
        height: 1.5,
        letterSpacing: 0.4,
      ),
      labelLarge: GoogleFonts.cairo(
        fontWeight: FontWeight.w700,
        fontSize: 16,
        letterSpacing: 0.5,
        height: 1.2,
      ),
      labelMedium: GoogleFonts.cairo(
        fontWeight: FontWeight.w600,
        fontSize: 14,
        letterSpacing: 0.5,
        height: 1.2,
      ),
      labelSmall: GoogleFonts.cairo(
        fontWeight: FontWeight.w600,
        fontSize: 12,
        letterSpacing: 0.5,
        height: 1.2,
      ),
    );
  }

  static Color _parseHex(String? hex) {
    final h = (hex ?? '').replaceAll('#', '').trim();
    if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
    if (h.length == 8) return Color(int.parse(h, radix: 16));
    return fallbackPrimary;
  }

  static BrandSchemes brandFromState(AppState state) {
    final primary = (state.primaryColorHex.trim().isNotEmpty)
        ? _parseHex(state.primaryColorHex)
        : fallbackPrimary;
    final secondary = (state.secondaryColorHex.trim().isNotEmpty)
        ? _parseHex(state.secondaryColorHex)
        : fallbackSecondary;

    ColorScheme withCustomizations(ColorScheme cs) {
      return cs.copyWith(
        primary: primary,
        secondary: secondary,
        error: errorColor,
        surface: cs.brightness == Brightness.light 
            ? Colors.white 
            : const Color(0xFF1A1A1A),
        surfaceContainerHighest: cs.brightness == Brightness.light 
            ? surfaceBg 
            : const Color(0xFF141414),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: cs.brightness == Brightness.light 
            ? const Color(0xFF1A1A1A) 
            : const Color(0xFFEEEEEE),
        onSurfaceVariant: cs.brightness == Brightness.light
            ? const Color(0xFF616161)
            : const Color(0xFF888888),
        outline: cs.brightness == Brightness.light 
            ? const Color(0xFFE0E0E0) 
            : const Color(0xFF2A2A2A),
        outlineVariant: cs.brightness == Brightness.light
            ? const Color(0xFFF5F5F5)
            : const Color(0xFF1E1E1E),
        shadow: cs.brightness == Brightness.light
            ? Colors.black.withOpacity(0.08)
            : Colors.black.withOpacity(0.5),
        surfaceTint: Colors.transparent,
      );
    }

    final light = withCustomizations(ColorScheme.fromSeed(
      seedColor: primary, 
      brightness: Brightness.light,
      surfaceTint: Colors.transparent,
    ));
    
    final dark = withCustomizations(ColorScheme.fromSeed(
      seedColor: primary, 
      brightness: Brightness.dark,
      surfaceTint: Colors.transparent,
    ));
    
    return BrandSchemes(light: light, dark: dark);
  }

  // Premium Border Radius
  static const double radiusSmall = 12.0;
  static const double radiusMedium = 16.0;
  static const double radiusLarge = 20.0;
  static const double radiusXLarge = 24.0;
  
  // Spacing System
  static const double spaceXS = 4.0;
  static const double spaceS = 8.0;
  static const double spaceM = 16.0;
  static const double spaceL = 24.0;
  static const double spaceXL = 32.0;
  static const double spaceXXL = 48.0;
}
