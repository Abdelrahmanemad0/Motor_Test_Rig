import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RigTheme {
  static const Color bg       = Color(0xFF0D0F12);
  static const Color card     = Color(0xFF141820);
  static const Color surface  = Color(0xFF1E2530);
  static const Color border   = Color(0xFF2A3240);
  static const Color accent   = Color(0xFF00E5A0);
  static const Color warning  = Color(0xFFFFAA22);
  static const Color alarm    = Color(0xFFFF3B3B);
  static const Color cyan     = Color(0xFF00CFFF);
  static const Color labelColor = Color(0xFF6B7A8D);

  static TextStyle get monoLarge => GoogleFonts.sourceCodePro(
    color: Colors.white,
    fontWeight: FontWeight.w500,
  );

  static TextStyle get label => GoogleFonts.sourceCodePro(
    color: labelColor,
    fontSize: 10,
    letterSpacing: 1.5,
    fontWeight: FontWeight.w400,
  );

  static TextStyle get sectionTitle => GoogleFonts.sourceCodePro(
    color: accent,
    fontSize: 11,
    letterSpacing: 2.5,
    fontWeight: FontWeight.w600,
  );

  static TextStyle get headerFont => GoogleFonts.rajdhani(
    color: Colors.white,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: 4,
  );

  static ThemeData get theme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    cardColor: card,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      secondary: cyan,
      surface: card,
      error: alarm,
    ),
    textTheme: GoogleFonts.sourceCodeProTextTheme(
      ThemeData.dark().textTheme,
    ),
  );
}