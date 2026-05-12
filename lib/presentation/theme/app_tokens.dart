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

const nordTokens = AppThemeTokens(
  id: 'nord',
  name: 'Nord',
  background: Color(0xFF2E3440),
  surface: Color(0xFF3B4252),
  foreground: Color(0xFFECEFF4),
  text: Color(0xFFECEFF4),
  mutedText: Color(0xFF4C566A),
  border: Color(0xFF434C5E),
  error: Color(0xFFBF616A),
  warning: Color(0xFFEBCB8B),
  accent: Color(0xFF88C0D0),
  cyan: Color(0xFF8FBCBB),
  green: Color(0xFFA3BE8C),
  orange: Color(0xFFD08770),
  pink: Color(0xFFB48EAD),
  purple: Color(0xFFB48EAD),
  red: Color(0xFFBF616A),
  yellow: Color(0xFFEBCB8B),
);

const monokaiTokens = AppThemeTokens(
  id: 'monokai',
  name: 'Monokai',
  background: Color(0xFF272822),
  surface: Color(0xFF3E3D32),
  foreground: Color(0xFFF8F8F2),
  text: Color(0xFFF8F8F2),
  mutedText: Color(0xFF75715E),
  border: Color(0xFF49483E),
  error: Color(0xFFF92672),
  warning: Color(0xFFE6DB74),
  accent: Color(0xFFA6E22E),
  cyan: Color(0xFF66D9E8),
  green: Color(0xFFA6E22E),
  orange: Color(0xFFFD971F),
  pink: Color(0xFFF92672),
  purple: Color(0xFFAE81FF),
  red: Color(0xFFF92672),
  yellow: Color(0xFFE6DB74),
);

const tokyoNightTokens = AppThemeTokens(
  id: 'tokyo_night',
  name: 'Tokyo Night',
  background: Color(0xFF1A1B26),
  surface: Color(0xFF1F2335),
  foreground: Color(0xFFC0CAF5),
  text: Color(0xFFC0CAF5),
  mutedText: Color(0xFF565F89),
  border: Color(0xFF292E42),
  error: Color(0xFFF7768E),
  warning: Color(0xFFE0AF68),
  accent: Color(0xFF7AA2F7),
  cyan: Color(0xFF7DCFFF),
  green: Color(0xFF9ECE6A),
  orange: Color(0xFFFF9E64),
  pink: Color(0xFFF7768E),
  purple: Color(0xFFBB9AF7),
  red: Color(0xFFF7768E),
  yellow: Color(0xFFE0AF68),
);

const gruvboxDarkTokens = AppThemeTokens(
  id: 'gruvbox_dark',
  name: 'Gruvbox',
  background: Color(0xFF282828),
  surface: Color(0xFF3C3836),
  foreground: Color(0xFFEBDBB2),
  text: Color(0xFFEBDBB2),
  mutedText: Color(0xFF928374),
  border: Color(0xFF504945),
  error: Color(0xFFFB4934),
  warning: Color(0xFFFABD2F),
  accent: Color(0xFFB8BB26),
  cyan: Color(0xFF8EC07C),
  green: Color(0xFFB8BB26),
  orange: Color(0xFFFE8019),
  pink: Color(0xFFD3869B),
  purple: Color(0xFFD3869B),
  red: Color(0xFFFB4934),
  yellow: Color(0xFFFABD2F),
);

// ── Light themes ──────────────────────────────────────────────────

const oneLightTokens = AppThemeTokens(
  id: 'one_light',
  name: 'One Light',
  background: Color(0xFFFAFAFA),
  surface: Color(0xFFEFEFF0),
  foreground: Color(0xFF383A42),
  text: Color(0xFF383A42),
  mutedText: Color(0xFFA0A1A7),
  border: Color(0xFFD4D4D5),
  error: Color(0xFFE45649),
  warning: Color(0xFFC18401),
  accent: Color(0xFF4078F2),
  cyan: Color(0xFF0184BC),
  green: Color(0xFF50A14F),
  orange: Color(0xFFC18401),
  pink: Color(0xFFE45649),
  purple: Color(0xFFA626A4),
  red: Color(0xFFE45649),
  yellow: Color(0xFFC18401),
);

const solarizedLightTokens = AppThemeTokens(
  id: 'solarized_light',
  name: 'Solarized',
  background: Color(0xFFFDF6E3),
  surface: Color(0xFFEEE8D5),
  foreground: Color(0xFF586E75),
  text: Color(0xFF586E75),
  mutedText: Color(0xFF93A1A1),
  border: Color(0xFFCCC4A8),
  error: Color(0xFFDC322F),
  warning: Color(0xFFCB4B16),
  accent: Color(0xFF268BD2),
  cyan: Color(0xFF2AA198),
  green: Color(0xFF859900),
  orange: Color(0xFFCB4B16),
  pink: Color(0xFFD33682),
  purple: Color(0xFF6C71C4),
  red: Color(0xFFDC322F),
  yellow: Color(0xFFB58900),
);

const githubDarkTokens = AppThemeTokens(
  id: 'github_dark',
  name: 'GitHub Dark',
  background: Color(0xFF0D1117),
  surface: Color(0xFF161B22),
  foreground: Color(0xFFC9D1D9),
  text: Color(0xFFC9D1D9),
  mutedText: Color(0xFF8B949E),
  border: Color(0xFF30363D),
  error: Color(0xFFF85149),
  warning: Color(0xFFD29922),
  accent: Color(0xFF58A6FF),
  cyan: Color(0xFF79C0FF),
  green: Color(0xFF3FB950),
  orange: Color(0xFFD29922),
  pink: Color(0xFFDB61A2),
  purple: Color(0xFFBC8CFF),
  red: Color(0xFFF85149),
  yellow: Color(0xFFE3B341),
);

const catppuccinMochaTokens = AppThemeTokens(
  id: 'catppuccin_mocha',
  name: 'Catppuccin',
  background: Color(0xFF1E1E2E),
  surface: Color(0xFF181825),
  foreground: Color(0xFFCDD6F4),
  text: Color(0xFFCDD6F4),
  mutedText: Color(0xFF6C7086),
  border: Color(0xFF313244),
  error: Color(0xFFF38BA8),
  warning: Color(0xFFFAB387),
  accent: Color(0xFF89B4FA),
  cyan: Color(0xFF94E2D5),
  green: Color(0xFFA6E3A1),
  orange: Color(0xFFFAB387),
  pink: Color(0xFFF5C2E7),
  purple: Color(0xFFCBA6F7),
  red: Color(0xFFF38BA8),
  yellow: Color(0xFFF9E2AF),
);

const allThemes = <String, AppThemeTokens>{
  // featured (top 4)
  'github_dark': githubDarkTokens,
  'one_dark': oneDarkTokens,
  'dracula': draculaTokens,
  'one_light': oneLightTokens,
  // more
  'nord': nordTokens,
  'monokai': monokaiTokens,
  'tokyo_night': tokyoNightTokens,
  'gruvbox_dark': gruvboxDarkTokens,
  'catppuccin_mocha': catppuccinMochaTokens,
  'solarized_light': solarizedLightTokens,
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
