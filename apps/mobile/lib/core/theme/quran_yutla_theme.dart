import 'package:flutter/material.dart';

/// Central Material 3 design system for Fadhkur (فذكر).
///
/// The palette keeps the existing indigo / teal / copper identity, while
/// moving all screens to semantic tokens instead of hard-coded colors.
class FadhkurTheme {
  static const Color indigo = Color(0xFF203A67);
  static const Color indigoDeep = Color(0xFF10233F);
  static const Color teal = Color(0xFF208C88);
  static const Color copper = Color(0xFFB96F49);
  static const Color pearl = Color(0xFFF8F7F3);
  static const Color night = Color(0xFF0B1422);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = dark
        ? const ColorScheme(
            brightness: Brightness.dark,
            primary: Color(0xFF9FC6FF),
            onPrimary: Color(0xFF00315E),
            primaryContainer: Color(0xFF174873),
            onPrimaryContainer: Color(0xFFD1E4FF),
            secondary: Color(0xFF79D6D1),
            onSecondary: Color(0xFF003735),
            secondaryContainer: Color(0xFF14504E),
            onSecondaryContainer: Color(0xFF9FF3EE),
            tertiary: Color(0xFFF2B694),
            onTertiary: Color(0xFF51200B),
            tertiaryContainer: Color(0xFF71361D),
            onTertiaryContainer: Color(0xFFFFDBCA),
            error: Color(0xFFFFB4AB),
            onError: Color(0xFF690005),
            errorContainer: Color(0xFF93000A),
            onErrorContainer: Color(0xFFFFDAD6),
            surface: Color(0xFF101A29),
            onSurface: Color(0xFFE0E8F4),
            surfaceContainerLowest: Color(0xFF09111D),
            surfaceContainerLow: Color(0xFF131E2D),
            surfaceContainer: Color(0xFF172231),
            surfaceContainerHigh: Color(0xFF202B3B),
            surfaceContainerHighest: Color(0xFF2A3545),
            onSurfaceVariant: Color(0xFFBCC7D8),
            outline: Color(0xFF8692A3),
            outlineVariant: Color(0xFF3D4858),
            shadow: Colors.black,
            scrim: Colors.black,
            inverseSurface: Color(0xFFE0E8F4),
            onInverseSurface: Color(0xFF26313F),
            inversePrimary: indigo,
            surfaceTint: Color(0xFF9FC6FF),
          )
        : const ColorScheme(
            brightness: Brightness.light,
            primary: indigo,
            onPrimary: Colors.white,
            primaryContainer: Color(0xFFD5E4FF),
            onPrimaryContainer: Color(0xFF082B50),
            secondary: teal,
            onSecondary: Colors.white,
            secondaryContainer: Color(0xFFB7EFEC),
            onSecondaryContainer: Color(0xFF003735),
            tertiary: copper,
            onTertiary: Colors.white,
            tertiaryContainer: Color(0xFFFFDBCA),
            onTertiaryContainer: Color(0xFF3A1606),
            error: Color(0xFFBA1A1A),
            onError: Colors.white,
            errorContainer: Color(0xFFFFDAD6),
            onErrorContainer: Color(0xFF410002),
            surface: Color(0xFFFFFBFF),
            onSurface: Color(0xFF1A1C20),
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: Color(0xFFF5F3F0),
            surfaceContainer: Color(0xFFEFEEEB),
            surfaceContainerHigh: Color(0xFFE9E8E5),
            surfaceContainerHighest: Color(0xFFE3E2DF),
            onSurfaceVariant: Color(0xFF44474E),
            outline: Color(0xFF74777F),
            outlineVariant: Color(0xFFC4C6CF),
            shadow: Colors.black,
            scrim: Colors.black,
            inverseSurface: Color(0xFF2F3035),
            onInverseSurface: Color(0xFFF1F0F5),
            inversePrimary: Color(0xFFA8C8FF),
            surfaceTint: indigo,
          );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? night : pearl,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    final text = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        height: 1.25,
        letterSpacing: 0,
      ),
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        height: 1.25,
        letterSpacing: 0,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        height: 1.3,
        letterSpacing: 0,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        height: 1.3,
        letterSpacing: 0,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.7, letterSpacing: 0),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.65, letterSpacing: 0),
      bodySmall: base.textTheme.bodySmall?.copyWith(height: 1.55, letterSpacing: 0),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
    );

    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.secondaryContainer,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.secondaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: text.labelLarge?.copyWith(
          color: scheme.onSecondaryContainer,
        ),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.secondary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.7),
        space: 1,
        thickness: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
