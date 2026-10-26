import 'package:flutter/material.dart';

/// Single Source of Truth (SSOT) Design Tokens untuk SmartBarber Ecosystem
/// Mematuhi rasio kontras WCAG 2.1 Level AA (> 4.5:1 untuk teks normal)
class AppColors {
  // --- PRIMARY ACCENT (Amber Gold) ---
  // Kontras rasio terhadap hitam: 8.7:1 (Lolos WCAG AAA)
  static const Color primary = Color(0xFFC3A47B);
  static const Color primaryLight = Color(0xFFD6BC97);
  static const Color primaryDark = Color(0xFFA68558);

  // --- BACKGROUND & SURFACES (Dark Architecture) ---
  static const Color background = Color(0xFF0C0A09); // True Black / Stone 950
  static const Color surface = Color(0xFF1C1917);    // Dark Stone Surface / Card
  static const Color surfaceElevated = Color(0xFF292524); // Modal & BottomSheet
  static const Color border = Color(0xFF44403C);     // Divider & Border line

  // --- TYPOGRAPHY CONTRAST COMPLIANCE (WCAG AA) ---
  static const Color textPrimary = Color(0xFFFAFAF9);   // 18.5:1 contrast
  static const Color textSecondary = Color(0xFFE7E5E4); // 13.2:1 contrast
  static const Color textMuted = Color(0xFF9E9E9E);     // 6.1:1 contrast (Replaces low-contrast #6B6B6B)

  // --- STATUS & ALERTS ---
  static const Color success = Color(0xFF10B981); // Emerald Green
  static const Color warning = Color(0xFFF59E0B); // Amber Warning
  static const Color danger = Color(0xFFEF4444);  // Red Alert
  static const Color info = Color(0xFF3B82F6);    // Blue Info

  // --- TICKET BADGES ---
  static const Color ticketGold = Color(0xFFC3A47B);
  static const Color ticketTextDark = Color(0xFF0C0A09);
}
