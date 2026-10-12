import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Quiet, neutral surfaces keep artwork prominent; copper marks active controls.
abstract final class SvaraTheme {
  static const lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xffa83e25),
    onPrimary: Color(0xffffffff),
    primaryContainer: Color(0xfffbe1d5),
    onPrimaryContainer: Color(0xff6a2311),
    secondary: Color(0xff615b56),
    onSecondary: Color(0xffffffff),
    secondaryContainer: Color(0xffe8e3dd),
    onSecondaryContainer: Color(0xff39342f),
    tertiary: Color(0xff56664a),
    onTertiary: Color(0xffffffff),
    tertiaryContainer: Color(0xffdce8cf),
    onTertiaryContainer: Color(0xff28361f),
    error: Color(0xffb32636),
    onError: Color(0xffffffff),
    errorContainer: Color(0xffffdadf),
    onErrorContainer: Color(0xff6d1020),
    surface: Color(0xfff7f3ee),
    onSurface: Color(0xff242326),
    onSurfaceVariant: Color(0xff625c57),
    surfaceDim: Color(0xffe4ddd5),
    surfaceBright: Color(0xfffffdfa),
    surfaceContainerLowest: Color(0xfffffdfa),
    surfaceContainerLow: Color(0xfff3efea),
    surfaceContainer: Color(0xfff0ebe5),
    surfaceContainerHigh: Color(0xffece6df),
    surfaceContainerHighest: Color(0xffe8e1d9),
    outline: Color(0xff887e75),
    outlineVariant: Color(0xffd4ccc3),
    inverseSurface: Color(0xff302e31),
    onInverseSurface: Color(0xfff5efea),
    inversePrimary: Color(0xffffad8e),
    surfaceTint: Colors.transparent,
    shadow: Color(0xff000000),
    scrim: Color(0xff000000),
  );

  static const darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xffffad8e),
    onPrimary: Color(0xff3b160b),
    primaryContainer: Color(0xff4a2a20),
    onPrimaryContainer: Color(0xffffdbcd),
    secondary: Color(0xffc7c1bb),
    onSecondary: Color(0xff302b27),
    secondaryContainer: Color(0xff302e31),
    onSecondaryContainer: Color(0xffe6dfd8),
    tertiary: Color(0xffbdd0ab),
    onTertiary: Color(0xff26371c),
    tertiaryContainer: Color(0xff39492e),
    onTertiaryContainer: Color(0xffdce8cf),
    error: Color(0xffffb3bd),
    onError: Color(0xff650c20),
    errorContainer: Color(0xff8c2036),
    onErrorContainer: Color(0xffffdadf),
    surface: Color(0xff151416),
    onSurface: Color(0xfff5efea),
    onSurfaceVariant: Color(0xffb9b1ab),
    surfaceDim: Color(0xff151416),
    surfaceBright: Color(0xff3d393b),
    surfaceContainerLowest: Color(0xff100f11),
    surfaceContainerLow: Color(0xff1b1a1c),
    surfaceContainer: Color(0xff232124),
    surfaceContainerHigh: Color(0xff302e31),
    surfaceContainerHighest: Color(0xff383538),
    outline: Color(0xff958b83),
    outlineVariant: Color(0xff494347),
    inverseSurface: Color(0xfff0ebe5),
    onInverseSurface: Color(0xff302b27),
    inversePrimary: Color(0xffa83e25),
    surfaceTint: Colors.transparent,
    shadow: Color(0xff000000),
    scrim: Color(0xff000000),
  );

  static ThemeData build(Brightness brightness) {
    final colors = brightness == Brightness.light ? lightScheme : darkScheme;
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      colorScheme: colors,
      scaffoldBackgroundColor: colors.surface,
      visualDensity: VisualDensity.standard,
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colors.outlineVariant),
    );
    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: brightness == Brightness.light
              ? Brightness.dark
              : Brightness.light,
          statusBarBrightness: brightness,
          systemNavigationBarColor: colors.surfaceContainerLowest,
          systemNavigationBarIconBrightness: brightness == Brightness.light
              ? Brightness.dark
              : Brightness.light,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.primary
                : colors.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => base.textTheme.labelMedium!.copyWith(
            color: states.contains(WidgetState.selected)
                ? colors.primary
                : colors.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerLowest,
        hintStyle: TextStyle(color: colors.onSurfaceVariant),
        prefixIconColor: colors.onSurfaceVariant,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceContainerLow,
        selectedColor: colors.primaryContainer,
        checkmarkColor: colors.onPrimaryContainer,
        labelStyle: base.textTheme.labelLarge!.copyWith(
          color: colors.onSurface,
        ),
        secondaryLabelStyle: base.textTheme.labelLarge!.copyWith(
          color: colors.onPrimaryContainer,
        ),
        side: BorderSide(color: colors.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return null;
            return states.contains(WidgetState.selected)
                ? colors.primary
                : null;
          }),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        thickness: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: colors.outline,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.inverseSurface,
        contentTextStyle: base.textTheme.bodyMedium!.copyWith(
          color: colors.onInverseSurface,
        ),
        actionTextColor: colors.inversePrimary,
      ),
    );
  }
}
