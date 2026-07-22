import 'package:flutter/material.dart';
import '../../app/themes/app_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  // Vibrant Indigo seeds for a modern, cool branding
  static ThemeData light({required Color seedColor}) {
    final base = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );
    final cs = base.copyWith(
      primary: seedColor,
      onPrimary: const Color(0xFFFFFFFF),
      primaryContainer: seedColor,
      onPrimaryContainer: const Color(0xFFFFFFFF),
      secondary: const Color(0xFF0A0A0A),
      onSecondary: const Color(0xFFFFFFFF),
      secondaryContainer: const Color(0xFFF2F2F2),
      onSecondaryContainer: const Color(0xFF0A0A0A),
      tertiary: const Color(0xFF0A0A0A),
      onTertiary: const Color(0xFFFFFFFF),
      tertiaryContainer: const Color(0xFFF2F2F2),
      onTertiaryContainer: const Color(0xFF0A0A0A),
      error: const Color(0xFF0A0A0A),
      onError: const Color(0xFFFFFFFF),
      errorContainer: const Color(0xFFF2F2F2),
      onErrorContainer: const Color(0xFF0A0A0A),
      surface: const Color(0xFFFFFFFF),
      onSurface: const Color(0xFF0A0A0A),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF7F7F7),
      surfaceContainer: const Color(0xFFF2F2F2),
      surfaceContainerHigh: const Color(0xFFE8E8E8),
      surfaceContainerHighest: const Color(0xFFE0E0E0),
      onSurfaceVariant: const Color(0xFF8E8E93),
      outline: const Color(0xFFEAEAEA),
      outlineVariant: const Color(0xFFF0F0F0),
      inverseSurface: const Color(0xFF0A0A0A),
      onInverseSurface: const Color(0xFFF5F5F5),
      inversePrimary: const Color(0xFFF5F5F5),
    );
    return _buildTheme(cs: cs, appColors: AppColors.light());
  }

  static ThemeData dark({required Color seedColor, bool oled = false}) {
    // Graphite palette — a single cohesive warm-neutral gray hue family so the
    // scaffold, cards, chips and inputs all read as one design system (the old
    // navy `surface` + gray containers looked mismatched). The container
    // ladder is widened so each step is visible, and `outline` is decoupled
    // from the containers so bordered chips/pills/inputs keep a crisp edge.
    // OLED keeps a pure-black surface with the same graphite containers.
    final bg = oled ? const Color(0xFF000000) : const Color(0xFF17171A);
    final base = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );
    // Brand seed handling. Only a *near-black* seed (the Monochrome Black
    // default) needs inverting — using it as `primary` on a dark surface makes
    // the button invisible. Every actual brand swatch (Indigo, Emerald, Rose,
    // Amber, Cyan, Violet) is light enough to show on graphite, so we keep it
    // verbatim and let the brand color carry through in dark mode too.
    //
    // `onPrimary`/`onPrimaryContainer` are picked per-seed for legible button
    // text: white on darker saturated seeds (Indigo, Violet, Rose), graphite on
    // brighter seeds (Emerald, Cyan, Amber).
    final seedLuminance = seedColor.computeLuminance();
    final isNearBlackSeed = seedLuminance < 0.1;
    final useLightOnPrimary = !isNearBlackSeed && seedLuminance < 0.35;
    final primary = isNearBlackSeed ? const Color(0xFFF5F5F5) : seedColor;
    final onPrimary = isNearBlackSeed
        ? const Color(0xFF17171A)
        : (useLightOnPrimary ? const Color(0xFFFFFFFF) : const Color(0xFF17171A));
    final primaryContainer = isNearBlackSeed
        ? const Color(0xFF2E2E33)
        : seedColor;
    final onPrimaryContainer = isNearBlackSeed
        ? const Color(0xFFF5F5F5)
        : (useLightOnPrimary ? const Color(0xFFFFFFFF) : const Color(0xFF17171A));

    final cs = base.copyWith(
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      secondary: const Color(0xFFF5F5F5),
      onSecondary: const Color(0xFF0A0A0A),
      secondaryContainer: const Color(0xFF262629),
      onSecondaryContainer: const Color(0xFFF5F5F5),
      tertiary: const Color(0xFFF5F5F5),
      onTertiary: const Color(0xFF0A0A0A),
      tertiaryContainer: const Color(0xFF262629),
      onTertiaryContainer: const Color(0xFFF5F5F5),
      error: const Color(0xFFF5F5F5),
      onError: const Color(0xFF0A0A0A),
      errorContainer: const Color(0xFF262629),
      onErrorContainer: const Color(0xFFF5F5F5),
      surface: bg,
      onSurface: const Color(0xFFF4F4F5),
      surfaceContainerLowest: bg,
      surfaceContainerLow:
          oled ? const Color(0xFF0E0E10) : const Color(0xFF1E1E21),
      surfaceContainer: const Color(0xFF262629),
      surfaceContainerHigh: const Color(0xFF2E2E33),
      surfaceContainerHighest: const Color(0xFF38383E),
      onSurfaceVariant: const Color(0xFFA1A1AA),
      outline: const Color(0xFF3A3A3F),
      outlineVariant: const Color(0xFF2A2A2E),
      inverseSurface: const Color(0xFFF5F5F5),
      onInverseSurface: const Color(0xFF0A0A0A),
      inversePrimary: isNearBlackSeed ? const Color(0xFF0A0A0A) : seedColor,
    );
    return _buildTheme(cs: cs, appColors: AppColors.dark());
  }

  static ThemeData _buildTheme({
    required ColorScheme cs,
    required AppColors appColors,
  }) {
    final textTheme = _buildTextTheme(cs.onSurface, cs.onSurfaceVariant);
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      textTheme: textTheme,
      scaffoldBackgroundColor: cs.surface,
      extensions: [appColors],
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        centerTitle: false,
        titleTextStyle: plusJakartaSans(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cs.outline),
        ),
        clipBehavior: Clip.antiAlias,
        color: cs.surfaceContainerLow,
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 64,
        backgroundColor: cs.surfaceContainerLow,
        indicatorColor: Colors.transparent,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(
          plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w500),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: cs.primary, size: 24);
          }
          return IconThemeData(color: cs.onSurfaceVariant, size: 24);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
        labelStyle: TextStyle(color: cs.onSurfaceVariant),
        floatingLabelStyle: TextStyle(color: cs.primary),
        errorStyle: plusJakartaSans(fontSize: 12, color: cs.error),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return cs.onSurface.withValues(alpha: 0.12);
            }
            return cs.primary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return cs.onSurface.withValues(alpha: 0.38);
            }
            return cs.onPrimary;
          }),
          minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          textStyle: WidgetStatePropertyAll(
            plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          elevation: const WidgetStatePropertyAll(0),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        shape: const CircleBorder(),
        extendedTextStyle: plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: cs.inverseSurface,
        contentTextStyle: plusJakartaSans(
          color: cs.onInverseSurface,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        actionTextColor: cs.inversePrimary,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        elevation: 0,
        titleTextStyle: plusJakartaSans(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        ),
        contentTextStyle: plusJakartaSans(
          fontSize: 14,
          color: cs.onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surface,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        elevation: 0,
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: cs.outline),
        backgroundColor: cs.surfaceContainerLow,
        selectedColor: cs.primary,
        // Unselected: dark text on light background
        labelStyle: plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: cs.onSurface,
        ),
        // Selected: light text on primary (dark) background
        secondaryLabelStyle: plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: cs.onPrimary,
        ),
        checkmarkColor: cs.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      ),
      dividerTheme: DividerThemeData(
        color: cs.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minVerticalPadding: 8,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: cs.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: plusJakartaSans(
          color: cs.onInverseSurface,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
        waitDuration: const Duration(milliseconds: 600),
        showDuration: const Duration(seconds: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
        textStyle: plusJakartaSans(fontSize: 14, color: cs.onSurface),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return cs.onPrimary;
          return cs.onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return cs.primary;
          return cs.surfaceContainerHighest;
        }),
      ),
    );
  }

  static TextTheme _buildTextTheme(Color primary, Color secondary) {
    return TextTheme(
      displayLarge: plusJakartaSans(
        fontSize: 57, fontWeight: FontWeight.w700, color: primary, height: 1.12,
      ),
      displayMedium: plusJakartaSans(
        fontSize: 45, fontWeight: FontWeight.w700, color: primary, height: 1.16,
      ),
      displaySmall: plusJakartaSans(
        fontSize: 36, fontWeight: FontWeight.w600, color: primary, height: 1.22,
      ),
      headlineLarge: plusJakartaSans(
        fontSize: 32, fontWeight: FontWeight.w700, color: primary, height: 1.25,
      ),
      headlineMedium: plusJakartaSans(
        fontSize: 28, fontWeight: FontWeight.w600, color: primary, height: 1.29,
      ),
      headlineSmall: plusJakartaSans(
        fontSize: 24, fontWeight: FontWeight.w600, color: primary, height: 1.33,
      ),
      titleLarge: plusJakartaSans(
        fontSize: 22, fontWeight: FontWeight.w700, color: primary, height: 1.27,
      ),
      titleMedium: plusJakartaSans(
        fontSize: 16, fontWeight: FontWeight.w600, color: primary, height: 1.5,
        letterSpacing: 0.15,
      ),
      titleSmall: plusJakartaSans(
        fontSize: 14, fontWeight: FontWeight.w600, color: primary, height: 1.43,
        letterSpacing: 0.1,
      ),
      bodyLarge: plusJakartaSans(
        fontSize: 16, fontWeight: FontWeight.w400, color: primary, height: 1.5,
        letterSpacing: 0.15,
      ),
      bodyMedium: plusJakartaSans(
        fontSize: 14, fontWeight: FontWeight.w400, color: primary, height: 1.43,
        letterSpacing: 0.25,
      ),
      bodySmall: plusJakartaSans(
        fontSize: 12, fontWeight: FontWeight.w400, color: secondary, height: 1.33,
        letterSpacing: 0.4,
      ),
      labelLarge: plusJakartaSans(
        fontSize: 14, fontWeight: FontWeight.w500, color: primary, height: 1.43,
        letterSpacing: 0.1,
      ),
      labelMedium: plusJakartaSans(
        fontSize: 12, fontWeight: FontWeight.w500, color: primary, height: 1.33,
        letterSpacing: 0.5,
      ),
      labelSmall: plusJakartaSans(
        fontSize: 11, fontWeight: FontWeight.w500, color: secondary, height: 1.45,
        letterSpacing: 0.5,
      ),
    );
  }
}
