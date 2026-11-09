import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 全项目共用的紫色按钮配色，之后新增页面也继承这里的样式。
class AppPalette {
  AppPalette._();

  static const lightPurple = Color(0xFFC4B5FD);
  static const deepPurple = Color(0xFF4C2D73);
  static const darkText = Color(0xFF21152F);
  static const lightText = Color(0xFFF5F0FF);
  static const purpleBorder = Color(0xFF9D80C4);
  static const disabledBackground = Color(0xFF382E47);
  static const disabledText = Color(0xFF9D92AD);
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    final primaryStyle = _glassStyle(AppPalette.lightPurple);
    final secondaryStyle = _glassStyle(AppPalette.deepPurple);
    final compactStyle = _glassStyle(AppPalette.deepPurple, compact: true);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppPalette.lightPurple,
        brightness: Brightness.dark,
        primary: AppPalette.lightPurple,
        onPrimary: AppPalette.darkText,
        secondary: AppPalette.deepPurple,
        onSecondary: AppPalette.lightText,
      ),
      scaffoldBackgroundColor: const Color(0xFF0B1020),
      filledButtonTheme: FilledButtonThemeData(style: primaryStyle),
      elevatedButtonTheme: ElevatedButtonThemeData(style: primaryStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(style: secondaryStyle),
      textButtonTheme: TextButtonThemeData(style: compactStyle),
      iconButtonTheme: IconButtonThemeData(
        style: compactStyle.copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
        ),
      ),
    );
  }

  // 用主题的背景层保留标准按钮的点击、焦点、禁用与语义行为。
  static ButtonStyle _glassStyle(Color tint, {bool compact = false}) {
    return ButtonStyle(
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(0),
      side: const WidgetStatePropertyAll(BorderSide.none),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      minimumSize: WidgetStatePropertyAll(Size(64, compact ? 40 : 52)),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? AppPalette.disabledText
            : AppPalette.lightText,
      ),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return Colors.transparent;
        if (states.contains(WidgetState.pressed)) {
          return Colors.white.withValues(alpha: 0.14);
        }
        if (states.contains(WidgetState.focused)) {
          return Colors.white.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.hovered)) {
          return Colors.white.withValues(alpha: 0.08);
        }
        return Colors.transparent;
      }),
      textStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: compact ? 14 : 15, fontWeight: FontWeight.w600),
      ),
      backgroundBuilder: (context, states, child) {
        final disabled = states.contains(WidgetState.disabled);
        final glassTint = disabled ? AppPalette.disabledBackground : tint;
        final opacity = disabled ? 0.22 : (compact ? 0.20 : 0.46);
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(
              sigmaX: compact ? 8 : 12,
              sigmaY: compact ? 8 : 12,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(
                      Colors.white.withValues(alpha: disabled ? 0.02 : 0.10),
                      glassTint.withValues(alpha: opacity),
                    ),
                    glassTint.withValues(alpha: opacity * 0.75),
                    glassTint.withValues(alpha: opacity),
                  ],
                  stops: const [0, 0.55, 1],
                ),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
