import 'package:flutter/material.dart';

class PremiumTheme extends ThemeExtension<PremiumTheme> {
  final Color primaryBlue;
  final Color textPrimary;
  final Color textSecondary;
  final Color glassColor;
  final Color glassBorder;
  final List<BoxShadow> glassShadow;
  final Color cardBg;
  final Color scaffoldBg;

  const PremiumTheme({
    required this.primaryBlue,
    required this.textPrimary,
    required this.textSecondary,
    required this.glassColor,
    required this.glassBorder,
    required this.glassShadow,
    required this.cardBg,
    required this.scaffoldBg,
  });

  static const light = PremiumTheme(
    primaryBlue: Color(0xFF001280),
    textPrimary: Color(0xFF1E293B),
    textSecondary: Color(0xFF64748B),
    glassColor: Color(0x80FFFFFF),
    glassBorder: Color(0xFFE2E8F0),
    glassShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 10)],
    cardBg: Colors.white,
    scaffoldBg: Color(0xFFF8F9FA),
  );

  static const dark = PremiumTheme(
    primaryBlue: Color(0xFF3B82F6),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFF94A3B8),
    glassColor: Color(0x800F172A),
    glassBorder: Color(0xFF1E293B),
    glassShadow: [BoxShadow(color: Color(0x00000000), blurRadius: 10)],
    cardBg: Color(0xFF1E293B),
    scaffoldBg: Color(0xFF0F172A),
  );

  @override
  ThemeExtension<PremiumTheme> copyWith() => this;

  @override
  ThemeExtension<PremiumTheme> lerp(ThemeExtension<PremiumTheme>? other, double t) => this;
}
