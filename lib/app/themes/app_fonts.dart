import 'package:flutter/material.dart';

/// Fully-local, drop-in replacements for the two `google_fonts` helpers the app
/// previously used. The fonts are bundled in `assets/fonts/` and declared as the
/// `PlusJakartaSans` / `SpaceGrotesk` families in `pubspec.yaml` — nothing is
/// fetched at runtime, so the app renders identically with no network.
///
/// These functions mirror the named-arg surface the call sites used
/// (`color`, `fontSize`, `fontWeight`, `height`, `letterSpacing`, `fontFeatures`,
/// `decoration`, `backgroundColor`, …) and return a `TextStyle` bound to the
/// bundled family. Swap `GoogleFonts.plusJakartaSans(` → `plusJakartaSans(`
/// (and `GoogleFonts.spaceGrotesk(` → `spaceGrotesk(`) and update the import.

const String kPlusJakartaSans = 'PlusJakartaSans';
const String kSpaceGrotesk = 'SpaceGrotesk';

TextStyle plusJakartaSans({
  Color? color,
  Color? backgroundColor,
  double? fontSize,
  FontWeight? fontWeight,
  FontStyle? fontStyle,
  double? letterSpacing,
  double? wordSpacing,
  double? height,
  TextLeadingDistribution? leadingDistribution,
  TextDecoration? decoration,
  Color? decorationColor,
  TextDecorationStyle? decorationStyle,
  double? decorationThickness,
  List<FontFeature>? fontFeatures,
}) =>
    _textStyle(
      fontFamily: kPlusJakartaSans,
      color: color,
      backgroundColor: backgroundColor,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      height: height,
      leadingDistribution: leadingDistribution,
      decoration: decoration,
      decorationColor: decorationColor,
      decorationStyle: decorationStyle,
      decorationThickness: decorationThickness,
      fontFeatures: fontFeatures,
    );

TextStyle spaceGrotesk({
  Color? color,
  Color? backgroundColor,
  double? fontSize,
  FontWeight? fontWeight,
  FontStyle? fontStyle,
  double? letterSpacing,
  double? wordSpacing,
  double? height,
  TextLeadingDistribution? leadingDistribution,
  TextDecoration? decoration,
  Color? decorationColor,
  TextDecorationStyle? decorationStyle,
  double? decorationThickness,
  List<FontFeature>? fontFeatures,
}) =>
    _textStyle(
      fontFamily: kSpaceGrotesk,
      color: color,
      backgroundColor: backgroundColor,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      height: height,
      leadingDistribution: leadingDistribution,
      decoration: decoration,
      decorationColor: decorationColor,
      decorationStyle: decorationStyle,
      decorationThickness: decorationThickness,
      fontFeatures: fontFeatures,
    );

TextStyle _textStyle({
  required String fontFamily,
  Color? color,
  Color? backgroundColor,
  double? fontSize,
  FontWeight? fontWeight,
  FontStyle? fontStyle,
  double? letterSpacing,
  double? wordSpacing,
  double? height,
  TextLeadingDistribution? leadingDistribution,
  TextDecoration? decoration,
  Color? decorationColor,
  TextDecorationStyle? decorationStyle,
  double? decorationThickness,
  List<FontFeature>? fontFeatures,
}) =>
    TextStyle(
      fontFamily: fontFamily,
      color: color,
      backgroundColor: backgroundColor,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      height: height,
      leadingDistribution: leadingDistribution,
      decoration: decoration,
      decorationColor: decorationColor,
      decorationStyle: decorationStyle,
      decorationThickness: decorationThickness,
      fontFeatures: fontFeatures,
    );