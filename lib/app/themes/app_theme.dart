import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  // Monochrome seeds — the scheme is fully overridden below; seeds only feed
  // the few tonal slots we don't set explicitly.
  static const _seedLight = Color(0xFF0A0A0A);
  static const _seedDark = Color(0xFFF5F5F5);

  static ThemeData light() {
    final base = ColorScheme.fromSeed(
      seedColor: _seedLight,
      brightness: Brightness.light,
    );
    final cs = base.copyWith(
      primary: const Color(0xFF0A0A0A),
      onPrimary: const Color(0xFFFFFFFF),
      primaryContainer: const Color(0xFF0A0A0A),
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

  static ThemeData dark({bool oled = false}) {
    final bg = oled ? const Color(0xFF000000) : const Color(0xFF0A0A0A);
    final base = ColorScheme.fromSeed(
      seedColor: _seedDark,
      brightness: Brightness.dark,
    );
    final cs = base.copyWith(
      primary: const Color(0xFFF5F5F5),
      onPrimary: const Color(0xFF0A0A0A),
      primaryContainer: const Color(0xFFF5F5F5),
      onPrimaryContainer: const Color(0xFF0A0A0A),
      secondary: const Color(0xFFF5F5F5),
      onSecondary: const Color(0xFF0A0A0A),
      secondaryContainer: const Color(0xFF1C1C1E),
      onSecondaryContainer: const Color(0xFFF5F5F5),
      tertiary: const Color(0xFFF5F5F5),
      onTertiary: const Color(0xFF0A0A0A),
      tertiaryContainer: const Color(0xFF1C1C1E),
      onTertiaryContainer: const Color(0xFFF5F5F5),
      error: const Color(0xFFF5F5F5),
      onError: const Color(0xFF0A0A0A),
      errorContainer: const Color(0xFF1C1C1E),
      onErrorContainer: const Color(0xFFF5F5F5),
      surface: bg,
      onSurface: const Color(0xFFF5F5F5),
      surfaceContainerLowest: bg,
      surfaceContainerLow: oled ? const Color(0xFF0F0F0F) : const Color(0xFF151517),
      surfaceContainer: const Color(0xFF1C1C1E),
      surfaceContainerHigh: const Color(0xFF2A2A2C),
      surfaceContainerHighest: const Color(0xFF333335),
      onSurfaceVariant: const Color(0xFF8E8E93),
      outline: const Color(0xFF2A2A2C),
      outlineVariant: const Color(0xFF1F1F21),
      inverseSurface: const Color(0xFFF5F5F5),
      onInverseSurface: const Color(0xFF0A0A0A),
      inversePrimary: const Color(0xFF0A0A0A),
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
        titleTextStyle: GoogleFonts.manrope(
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
        color: cs.surface,
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 64,
        backgroundColor: cs.surface,
        indicatorColor: Colors.transparent,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(
          GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerLow,
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
        errorStyle: GoogleFonts.inter(fontSize: 12, color: cs.error),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return cs.onSurface.withValues(alpha: 0.12);
            }
            return cs.onSurface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return cs.onSurface.withValues(alpha: 0.38);
            }
            return cs.surface;
          }),
          minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          textStyle: WidgetStatePropertyAll(
            GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          elevation: const WidgetStatePropertyAll(0),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        backgroundColor: cs.onSurface,
        foregroundColor: cs.surface,
        shape: const CircleBorder(),
        extendedTextStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: cs.inverseSurface,
        contentTextStyle: GoogleFonts.inter(
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
        titleTextStyle: GoogleFonts.manrope(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        ),
        contentTextStyle: GoogleFonts.inter(
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
        backgroundColor: cs.surface,
        selectedColor: cs.primary,
        labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
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
          textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: cs.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: GoogleFonts.inter(
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
        textStyle: GoogleFonts.inter(fontSize: 14, color: cs.onSurface),
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
      displayLarge: GoogleFonts.manrope(
        fontSize: 57, fontWeight: FontWeight.w700, color: primary, height: 1.12,
      ),
      displayMedium: GoogleFonts.manrope(
        fontSize: 45, fontWeight: FontWeight.w700, color: primary, height: 1.16,
      ),
      displaySmall: GoogleFonts.manrope(
        fontSize: 36, fontWeight: FontWeight.w600, color: primary, height: 1.22,
      ),
      headlineLarge: GoogleFonts.manrope(
        fontSize: 32, fontWeight: FontWeight.w700, color: primary, height: 1.25,
      ),
      headlineMedium: GoogleFonts.manrope(
        fontSize: 28, fontWeight: FontWeight.w600, color: primary, height: 1.29,
      ),
      headlineSmall: GoogleFonts.manrope(
        fontSize: 24, fontWeight: FontWeight.w600, color: primary, height: 1.33,
      ),
      titleLarge: GoogleFonts.manrope(
        fontSize: 22, fontWeight: FontWeight.w700, color: primary, height: 1.27,
      ),
      titleMedium: GoogleFonts.manrope(
        fontSize: 16, fontWeight: FontWeight.w600, color: primary, height: 1.5,
        letterSpacing: 0.15,
      ),
      titleSmall: GoogleFonts.manrope(
        fontSize: 14, fontWeight: FontWeight.w600, color: primary, height: 1.43,
        letterSpacing: 0.1,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16, fontWeight: FontWeight.w400, color: primary, height: 1.5,
        letterSpacing: 0.15,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w400, color: primary, height: 1.43,
        letterSpacing: 0.25,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12, fontWeight: FontWeight.w400, color: secondary, height: 1.33,
        letterSpacing: 0.4,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w500, color: primary, height: 1.43,
        letterSpacing: 0.1,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12, fontWeight: FontWeight.w500, color: primary, height: 1.33,
        letterSpacing: 0.5,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 11, fontWeight: FontWeight.w500, color: secondary, height: 1.45,
        letterSpacing: 0.5,
      ),
    );
  }
}
