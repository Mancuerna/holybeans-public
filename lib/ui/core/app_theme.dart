import 'package:flutter/material.dart';

/// HolyBeans' look: a lab notebook for coffee.
///
/// Uses grey surfaces, white sheets, ink, and cherry red (the coffee fruit) for
/// actions and selected controls. Frozen stock has its own blue accent. Text
/// uses IBM Plex Sans; numbers use its condensed cut with tabular figures so
/// they can be read and compared. Color and typography
/// tokens are defined here for both light and dark themes.
abstract final class AppTheme {
  /// Family names as declared in pubspec.yaml.
  static const text = 'Plex';
  static const condensed = 'PlexCondensed';

  static ThemeData light() => _build(_lightColors);
  static ThemeData dark() => _build(_darkColors);

  /// Numbers meant to be read at a glance and compared: the condensed cut,
  /// semibold, with figures of equal width.
  static TextStyle figures(TextStyle? base) =>
      (base ?? const TextStyle()).copyWith(
        fontFamily: condensed,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
        letterSpacing: 0,
      );

  static const _lightColors = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF9E1F35),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFF4DEE1),
    onPrimaryContainer: Color(0xFF5C0F1E),
    secondary: Color(0xFF4A4642),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFDEDFD9),
    onSecondaryContainer: Color(0xFF221E1B),
    tertiary: Color(0xFF4D6B2F),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFE0E8D2),
    onTertiaryContainer: Color(0xFF2B3D19),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF9DEDC),
    onErrorContainer: Color(0xFF410E0B),
    surface: Color(0xFFEEEFEB),
    onSurface: Color(0xFF221E1B),
    onSurfaceVariant: Color(0xFF5F5B55),
    surfaceDim: Color(0xFFDADBD6),
    surfaceBright: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF7F7F4),
    surfaceContainer: Color(0xFFE8E9E4),
    surfaceContainerHigh: Color(0xFFE2E3DE),
    surfaceContainerHighest: Color(0xFFDADBD6),
    outline: Color(0xFF8D8983),
    outlineVariant: Color(0xFFD6D7D1),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF2F2B28),
    onInverseSurface: Color(0xFFF2F1EC),
    inversePrimary: Color(0xFFFFB2BC),
    surfaceTint: Color(0x00000000),
  );

  static const _darkColors = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFE06573),
    onPrimary: Color(0xFF2B0309),
    primaryContainer: Color(0xFF6F1426),
    onPrimaryContainer: Color(0xFFFFD9DE),
    secondary: Color(0xFFCBC6BF),
    onSecondary: Color(0xFF2F2B28),
    secondaryContainer: Color(0xFF3B3936),
    onSecondaryContainer: Color(0xFFECEBE6),
    tertiary: Color(0xFFADC78E),
    onTertiary: Color(0xFF1C2C0B),
    tertiaryContainer: Color(0xFF34481F),
    onTertiaryContainer: Color(0xFFD9E7C6),
    error: Color(0xFFF2B8B5),
    onError: Color(0xFF601410),
    errorContainer: Color(0xFF8C1D18),
    onErrorContainer: Color(0xFFF9DEDC),
    surface: Color(0xFF1B1A18),
    onSurface: Color(0xFFECEBE6),
    onSurfaceVariant: Color(0xFFB7B3AC),
    surfaceDim: Color(0xFF1B1A18),
    surfaceBright: Color(0xFF3A3835),
    surfaceContainerLowest: Color(0xFF242320),
    surfaceContainerLow: Color(0xFF211F1D),
    surfaceContainer: Color(0xFF2A2926),
    surfaceContainerHigh: Color(0xFF33312E),
    surfaceContainerHighest: Color(0xFF3D3B38),
    outline: Color(0xFF8F8B85),
    outlineVariant: Color(0xFF3E3C39),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFECEBE6),
    onInverseSurface: Color(0xFF2F2B28),
    inversePrimary: Color(0xFF9E1F35),
    surfaceTint: Color(0x00000000),
  );

  /// Corner radii by role: controls, grouped content, sheets.
  static const radiusSmall = 8.0;
  static const radiusMedium = 12.0;
  static const radiusLarge = 28.0;

  static TextTheme _textTheme(ColorScheme colors) {
    final typography = Typography.material2021(colorScheme: colors);
    final themed =
        (colors.brightness == Brightness.dark
                ? typography.white
                : typography.black)
            .apply(fontFamily: text);
    TextStyle display(TextStyle? style) =>
        style!.copyWith(fontFamily: condensed, fontWeight: FontWeight.w600);
    TextStyle title(TextStyle? style) =>
        style!.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0);
    return themed
        .copyWith(
          displayLarge: display(themed.displayLarge),
          displayMedium: display(themed.displayMedium),
          displaySmall: display(themed.displaySmall),
          headlineLarge: display(themed.headlineLarge),
          headlineMedium: display(themed.headlineMedium),
          headlineSmall: title(themed.headlineSmall),
          titleLarge: title(themed.titleLarge),
          titleMedium: title(themed.titleMedium),
          titleSmall: title(themed.titleSmall),
          labelLarge: themed.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        )
        .apply(bodyColor: colors.onSurface, displayColor: colors.onSurface);
  }

  static ThemeData _build(ColorScheme colors) {
    final textTheme = _textTheme(colors);
    const small = BorderRadius.all(Radius.circular(radiusSmall));
    const medium = BorderRadius.all(Radius.circular(radiusMedium));
    const buttonShape = StadiumBorder();
    final sheet = colors.surfaceContainerLowest;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      fontFamily: text,
      textTheme: textTheme,
      scaffoldBackgroundColor: colors.surface,
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall?.copyWith(
          fontFamily: condensed,
          fontSize: 25,
        ),
      ),
      cardTheme: CardThemeData(
        color: sheet,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: const RoundedRectangleBorder(borderRadius: medium),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: sheet,
        modalBackgroundColor: sheet,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: colors.outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(radiusLarge),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: sheet,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusLarge)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: sheet,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.onPrimaryContainer
                : colors.onSurfaceVariant,
          ),
        ),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelMedium?.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
            color: states.contains(WidgetState.selected)
                ? colors.onSurface
                : colors.onSurfaceVariant,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colors.onSurface,
        unselectedLabelColor: colors.onSurfaceVariant,
        labelStyle: textTheme.titleSmall,
        unselectedLabelStyle: textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w400,
        ),
        indicatorColor: colors.primary,
        dividerColor: colors.outlineVariant,
      ),
      inputDecorationTheme: InputDecorationTheme(
        // Hints explain what a field changes; they wrap instead of ending in
        // an ellipsis.
        helperMaxLines: 3,
        filled: true,
        fillColor: colors.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: small,
          borderSide: BorderSide(color: colors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: small,
          borderSide: BorderSide(color: colors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: small,
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(borderRadius: small),
        side: BorderSide(color: colors.outlineVariant),
        backgroundColor: sheet,
        selectedColor: colors.primaryContainer,
        checkmarkColor: colors.onPrimaryContainer,
        labelStyle: textTheme.labelLarge?.copyWith(color: colors.onSurface),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        elevation: 1,
        highlightElevation: 2,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        extendedTextStyle: textTheme.titleMedium,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: buttonShape,
          textStyle: textTheme.titleSmall,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: buttonShape,
          foregroundColor: colors.onSurface,
          side: BorderSide(color: colors.outline),
          textStyle: textTheme.titleSmall,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        // Ink, not the accent: the red stays for the main action.
        style: TextButton.styleFrom(
          shape: buttonShape,
          foregroundColor: colors.onSurface,
          textStyle: textTheme.labelLarge,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: buttonShape,
          selectedBackgroundColor: colors.primaryContainer,
          selectedForegroundColor: colors.onPrimaryContainer,
          side: BorderSide(color: colors.outline),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: medium),
        backgroundColor: colors.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colors.onInverseSurface,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: medium),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }
}
