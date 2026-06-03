import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Core Colors
  static const Color primary = Color(0xFFDAA520);
  static const Color secondary = Color(0xFF9C6A26);
  static const Color background = Color(0xFF0E0C0B);
  static const Color cardBg = Color(0xFF1A1512);
  static const Color textPrimary = Color(0xFFF8F6F2);
  static const Color textMuted = Color(0xFF9C958B);
  static const Color border = Color(0xFF373125);
  static const Color borderHalf = Color(0x80373125);
  static const Color success = Color(0xFF0FB56A);
  static const Color warning = Color(0xFFF4A300);
  static const Color error = Color(0xFFDC2626);

  // Gradients
  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF231D1A), Color(0xFF110F0D)],
  );

  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFDAA520), Color(0xFF9C6A26)],
  );

  // Effects
  static const BoxShadow glowEffect = BoxShadow(
    color: Color(0x4DDAA520), // rgba(218,165,32,0.3)
    blurRadius: 40,
    spreadRadius: 0,
  );

  // Global ThemeData
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      textTheme: GoogleFonts.interTextTheme().apply(
        bodyColor: textPrimary,
        displayColor: primary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        iconTheme: const IconThemeData(color: primary),
        titleTextStyle: GoogleFonts.playfairDisplay(
            color: primary,
            fontSize: 24,
            fontWeight: FontWeight.w600
        ),
      ),
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: cardBg,
        error: error,
      ),
    );
  }
}