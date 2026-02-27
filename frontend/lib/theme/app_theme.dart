import 'package:flutter/material.dart';

/// Central theme configuration for Vitable Health chat app.
/// All color literals live here — never scatter them across the UI layer.
abstract final class AppTheme {
  // ── Brand Colors ──────────────────────────────────────────────────────────

  /// User message bubble background (Vitable green tint)
  static const Color userBubbleBg = Color(0xFFBFF4C8);

  /// User message text
  static const Color userBubbleText = Color(0xFF003C32);

  /// AI message bubble background (Vitable dark green)
  static const Color aiBubbleBg = Color(0xFF003C32);

  /// AI message text
  static const Color aiMessageText = Colors.white;

  /// Accent / button color
  static const Color accent = Color(0xFF3C6DD8);

  /// Secondary accent (calendar buttons)
  static const Color accentSecondary = Color(0xFF682C46);

  /// White background inside chat container
  static const Color chatBg = Colors.white;

  /// Dark outer page background (web only)
  static const Color outerBg = Color(0xFF1E1E1E);

  /// Error bubble background
  static const Color errorBubbleBg = Color(0xFFFFEDED);

  /// Error text
  static const Color errorText = Color(0xFF9B1C1C);

  /// Input field border color
  static const Color inputBorder = Color(0xFFDDDDDD);

  /// Disabled input field border color
  static const Color inputBorderDisabled = Color(0xFFEEEEEE);

  /// Input hint text color
  static const Color inputHint = Color(0xFFAAAAAA);

  /// Disabled input field background
  static const Color inputBgDisabled = Color(0xFFF5F5F5);

  /// Web chat window border (white at 12% opacity)
  static const Color webWindowBorder = Colors.white12;

  /// Disabled send button color
  static const Color sendButtonDisabled = Color(0xFFD4D4D4);

  /// Disabled send button icon color
  static const Color sendButtonIconDisabled = Color(0xFF9E9E9E);

  // ── Layout ────────────────────────────────────────────────────────────────

  /// Maximum width for bubble content (fraction of screen width)
  static const double maxBubbleWidthFraction = 0.80;

  /// Maximum width for the centered chat column on web
  static const double maxChatColumnWidth = 860.0;

  /// Bubble border radius
  static const double bubbleRadius = 16.0;

  // ── Typography ────────────────────────────────────────────────────────────

  static const TextStyle bubbleTextStyle = TextStyle(
    fontSize: 15.0,
    height: 1.45,
  );

  static const TextStyle inputTextStyle = TextStyle(
    fontSize: 15.0,
  );

  // ── Material Theme ────────────────────────────────────────────────────────

  static ThemeData get lightTheme => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: aiBubbleBg,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: chatBg,
        useMaterial3: true,
      );
}
