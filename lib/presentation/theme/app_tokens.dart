import 'package:flutter/material.dart';

// ── Theme Token Model ──────────────────────────────────────────────

class AppThemeTokens {
  final String id;
  final String name;

  // Surfaces
  final Color background;
  final Color surface;
  final Color foreground;

  // Text
  final Color text;
  final Color mutedText;

  // Borders & separators
  final Color border;

  // Status
  final Color error;
  final Color warning;

  // Accents
  final Color accent;
  final Color cyan;
  final Color green;
  final Color orange;
  final Color pink;
  final Color purple;
  final Color red;
  final Color yellow;

  const AppThemeTokens({
    required this.id,
    required this.name,
    required this.background,
    required this.surface,
    required this.foreground,
    required this.text,
    required this.mutedText,
    required this.border,
    required this.error,
    required this.warning,
    required this.accent,
    required this.cyan,
    required this.green,
    required this.orange,
    required this.pink,
    required this.purple,
    required this.red,
    required this.yellow,
  });
}

// ── Active Theme Registry ──────────────────────────────────────────

AppThemeTokens _activeTokens = draculaTokens;

AppThemeTokens get $tokens => _activeTokens;

void setAppTheme(String themeId) {
  _activeTokens = allThemes[themeId] ?? draculaTokens;
}

void setAppThemeTokens(AppThemeTokens tokens) {
  _activeTokens = tokens;
}

// ── Theme Presets ──────────────────────────────────────────────────

const draculaTokens = AppThemeTokens(
  id: 'dracula',
  name: 'Dracula',
  background: Color(0xFF282A36),
  surface: Color(0xFF44475A),
  foreground: Color(0xFFF8F8F2),
  text: Color(0xFFF8F8F2),
  mutedText: Color(0xFF6272A4),
  border: Color(0xFF6272A4),
  error: Color(0xFFFF5555),
  warning: Color(0xFFF1FA8C),
  accent: Color(0xFF50FA7B),
  cyan: Color(0xFF8BE9FD),
  green: Color(0xFF50FA7B),
  orange: Color(0xFFFFB86C),
  pink: Color(0xFFFF79C6),
  purple: Color(0xFFBD93F9),
  red: Color(0xFFFF5555),
  yellow: Color(0xFFF1FA8C),
);

const oneDarkTokens = AppThemeTokens(
  id: 'one_dark',
  name: 'One Dark',
  background: Color(0xFF282C34),
  surface: Color(0xFF2C313A),
  foreground: Color(0xFFABB2BF),
  text: Color(0xFFABB2BF),
  mutedText: Color(0xFF5C6370),
  border: Color(0xFF3E4451),
  error: Color(0xFFE06C75),
  warning: Color(0xFFD19A66),
  accent: Color(0xFF61AFEF),
  cyan: Color(0xFF56B6C2),
  green: Color(0xFF98C379),
  orange: Color(0xFFD19A66),
  pink: Color(0xFFC678DD),
  purple: Color(0xFFC678DD),
  red: Color(0xFFE06C75),
  yellow: Color(0xFFE5C07B),
);

const allThemes = <String, AppThemeTokens>{
  'dracula': draculaTokens,
  'one_dark': oneDarkTokens,
};

// ── Spacing Constants ──────────────────────────────────────────────

abstract class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

// ── Radius Constants ───────────────────────────────────────────────

abstract class AppRadii {
  static const double none = 0;
  static const double sm = 4;
  static const double md = 8;
}
