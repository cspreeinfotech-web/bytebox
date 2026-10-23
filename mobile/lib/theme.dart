import 'package:flutter/material.dart';

/// THE ONLY place colours are defined. Theme A · Royal Violet.
class AppColors {
  static const primary = Color(0xFF7C5CFF);
  static const accent = Color(0xFFFF5CA8);
  static const background = Color(0xFF0A0A14);
  static const surface = Color(0xFF14142A);
  static const surfaceHigh = Color(0xFF1E1E38);
  static const outline = Color(0xFF2E2E52);
  static const text = Color(0xFFF4F3FF);
  static const textMuted = Color(0xFF9C9AC0);
  static const premium = Color(0xFFFFC94D); // gold — Premium only
  static const success = Color(0xFF34D399);
  static const warning = Color(0xFFFBBF24);
  static const danger = Color(0xFFF87171);
  static const scrim = Color(0xCC000000);
  static const scrimLight = Color(0x66000000);
  static const onPrimary = Color(0xFFFFFFFF);
  static const transparent = Color(0x00000000);

  static const brandGradient = LinearGradient(
    colors: [primary, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const premiumGradient = LinearGradient(
    colors: [Color(0xFF3A2A8C), primary, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const thumbScrim = LinearGradient(
    colors: [Color(0x00000000), scrim],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

class AppRadius {
  static const button = 14.0;
  static const card = 16.0;
  static const chip = 20.0;
}

class AppTheme {
  static const font = 'Poppins';

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.surface,
      onPrimary: AppColors.onPrimary,
      onSurface: AppColors.text,
      error: AppColors.danger,
      outline: AppColors.outline,
    );
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button));
    const buttonSize = Size.fromHeight(48);
    const buttonText = TextStyle(fontFamily: font, fontWeight: FontWeight.w700, fontSize: 15);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: font,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontFamily: font, fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize, shape: buttonShape, textStyle: buttonText,
          backgroundColor: AppColors.primary, foregroundColor: AppColors.onPrimary,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(minimumSize: buttonSize, shape: buttonShape, textStyle: buttonText),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize, shape: buttonShape, textStyle: buttonText,
          foregroundColor: AppColors.text,
          side: const BorderSide(color: AppColors.outline, width: 1.4),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary, textStyle: buttonText),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        labelStyle: const TextStyle(color: AppColors.textMuted),
        hintStyle: const TextStyle(color: AppColors.textMuted),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primary,
        labelStyle: const TextStyle(fontFamily: font, color: AppColors.text, fontWeight: FontWeight.w500),
        side: const BorderSide(color: AppColors.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.chip)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.22),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontFamily: font, fontSize: 11, fontWeight: FontWeight.w500),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textMuted),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      dividerTheme: const DividerThemeData(color: AppColors.outline, thickness: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
    );
  }
}
