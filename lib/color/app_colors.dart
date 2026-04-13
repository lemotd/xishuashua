import 'package:flutter/material.dart';

class AppColors {
  // ── Light Mode ──
  static const light = _LightColors();
  // ── Dark Mode ──
  static const dark = _DarkColors();
}

class _LightColors {
  const _LightColors();

  final Color background = const Color(0xFFF5F5F5);
  final Color surface = const Color(0xFFFFFFFF);
  final Color primary = const Color(0xFFFF2D55);
  final Color primaryGlow = const Color(0x40FF2D55);
  final Color textPrimary = const Color(0xFF1C1C1E);
  final Color textSecondary = const Color(0xFF8E8E93);
  final Color textHint = const Color(0xFFAEAEB2);
  final Color icon = const Color(0xFF1C1C1E);
  final Color iconInactive = const Color(0xFF8E8E93);
  final Color divider = const Color(0xFFE5E5EA);
  final Color overlay = const Color(0x99000000);
  final Color gradientStart = const Color(0xDD000000);
  final Color gradientEnd = Colors.transparent;
  final Color inputFill = const Color(0xFFF2F2F7);
  final Color cardBackground = const Color(0xFFFFFFFF);
  final Color shimmer = const Color(0xFFE5E5EA);
  final Color shadow = const Color(0x38000000);
  final Color avatarBg = const Color(0xFFFF2D55);
  final Color onSurface = const Color(0xFF1C1C1E);
  final Color onSurfaceTertiary = const Color(0xFFC7C7CC);
  final Color onSurfaceQuaternary = const Color(0xFFAEAEB2);
  final Color progressPlayed = const Color(0xCCFFFFFF);
}

class _DarkColors {
  const _DarkColors();

  final Color background = const Color(0xFF000000);
  final Color surface = const Color(0xFF1C1C1E);
  final Color primary = const Color(0xFFFF2D55);
  final Color primaryGlow = const Color(0x80FF2D55);
  final Color highlightPurple = const Color(0xFF8370FF);
  final Color highlightPurpleGlow = const Color(0x808370FF);
  final Color textPrimary = const Color(0xFFFFFFFF);
  final Color textSecondary = const Color(0xB3FFFFFF);
  final Color textHint = const Color(0x61FFFFFF);
  final Color icon = const Color(0xFFFFFFFF);
  final Color iconInactive = const Color(0xB3FFFFFF);
  final Color divider = const Color(0x1FFFFFFF);
  final Color overlay = const Color(0xDD000000);
  final Color gradientStart = const Color(0xDD000000);
  final Color gradientEnd = Colors.transparent;
  final Color inputFill = const Color(0x1AFFFFFF);
  final Color cardBackground = const Color(0xFF1C1C1E);
  final Color shimmer = const Color(0x1AFFFFFF);
  final Color shadow = const Color(0x38000000);
  final Color avatarBg = const Color(0xFFFF2D55);
  final Color onSurface = const Color(0xFFFFFFFF);
  final Color onSurfaceTertiary = const Color(0x99FFFFFF); // 60%
  final Color onSurfaceQuaternary = const Color(0x61FFFFFF);
  final Color progressPlayed = const Color(0xCCFFFFFF); // #FFFFFF 80%
  final Color surfaceContainerHigh = const Color(0x24FFFFFF); // #FFFFFF 14%
}
