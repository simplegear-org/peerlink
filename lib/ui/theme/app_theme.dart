import 'package:flutter/material.dart';

import 'app_appearance.dart';

class AppTheme {
  static const String fontFamily = 'Roboto';

  static AppAppearance _activeAppearance = AppAppearance.icon1;

  static AppAppearance get activeAppearance => _activeAppearance;
  static AppPalette get _palette => _activeAppearance.palette;

  static Color get sand => _palette.sand;
  static Color get paper => _palette.paper;
  static Color get ink => _palette.ink;
  static Color get muted => _palette.muted;
  static Color get stroke => _palette.stroke;
  static Color get accent => _palette.accent;
  static Color get accentSoft => _palette.accentSoft;
  static Color get pine => _palette.pine;
  static Color get pineSoft => _palette.pineSoft;
  static Color get surfaceRaised => _palette.surfaceRaised;
  static Color get surfaceMuted => _palette.surfaceMuted;

  static void applyAppearance(AppAppearance appearance) {
    _activeAppearance = appearance;
  }

  static ThemeData light([AppAppearance appearance = AppAppearance.icon1]) {
    applyAppearance(appearance);
    final palette = appearance.palette;
    final scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: palette.accent,
      onPrimary: Colors.white,
      secondary: palette.pine,
      onSecondary: palette.sand,
      error: const Color(0xFFFF6B6B),
      onError: Colors.white,
      surface: palette.paper,
      onSurface: palette.ink,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.sand,
      canvasColor: palette.sand,
      splashFactory: InkSparkle.splashFactory,
      textTheme: TextTheme(
        displaySmall: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          height: 1.02,
          color: palette.ink,
        ),
        headlineMedium: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          height: 1.05,
          color: palette.ink,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: palette.ink,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: palette.ink,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: palette.ink, height: 1.35),
        bodyMedium: TextStyle(fontSize: 14, color: palette.muted, height: 1.35),
        bodySmall: TextStyle(fontSize: 12, color: palette.muted, height: 1.35),
        labelLarge: TextStyle(
          fontSize: 14,
          color: palette.ink,
          fontWeight: FontWeight.w700,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          color: palette.muted,
          fontWeight: FontWeight.w600,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          color: palette.muted,
          fontWeight: FontWeight.w600,
        ),
      ).apply(fontFamily: fontFamily),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: palette.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: palette.ink,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.surfaceMuted,
        elevation: 0,
        indicatorColor: palette.accentSoft,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final active = states.contains(WidgetState.selected);
          return IconThemeData(color: active ? palette.ink : palette.muted);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final active = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? palette.ink : palette.muted,
          );
        }),
      ),
      cardTheme: CardThemeData(
        color: palette.paper,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: palette.stroke),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceRaised,
        hintStyle: TextStyle(fontFamily: fontFamily, color: palette.muted),
        labelStyle: TextStyle(fontFamily: fontFamily, color: palette.muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: palette.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: palette.accent, width: 1.4),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: palette.stroke),
        ),
      ),
      iconTheme: IconThemeData(color: palette.ink),
      dividerColor: palette.stroke,
      dividerTheme: DividerThemeData(
        color: palette.stroke,
        space: 1,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surfaceRaised,
        contentTextStyle: TextStyle(fontFamily: fontFamily, color: palette.ink),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: palette.stroke),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: palette.stroke),
        ),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: palette.ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: palette.muted,
          fontSize: 14,
          height: 1.4,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          side: BorderSide(color: palette.stroke),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: palette.stroke,
          disabledForegroundColor: palette.muted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.ink,
          side: BorderSide(color: palette.stroke),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.accent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.accent,
        circularTrackColor: palette.stroke,
        linearTrackColor: palette.surfaceRaised,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.accent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
    );
  }
}
