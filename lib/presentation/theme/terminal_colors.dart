import 'package:flutter/material.dart';

abstract class TColors {
  // Dracula theme palette
  static const background = Color(0xFF282A36);
  static const surface = Color(0xFF44475A);
  static const foreground = Color(0xFFF8F8F2);
  static const comment = Color(0xFF6272A4);
  static const cyan = Color(0xFF8BE9FD);
  static const green = Color(0xFF50FA7B);
  static const orange = Color(0xFFFFB86C);
  static const pink = Color(0xFFFF79C6);
  static const purple = Color(0xFFBD93F9);
  static const red = Color(0xFFFF5555);
  static const yellow = Color(0xFFF1FA8C);

  // Semantic aliases
  static const text = foreground;
  static const mutedText = comment;
  static const accent = green;
  static const accentText = green;
  static const error = red;
  static const warning = yellow;
  static const border = comment;
}
