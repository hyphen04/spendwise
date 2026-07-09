import 'package:flutter/material.dart';

/// Parses a `#RRGGBB` / `RRGGBB` hex string into a fully-opaque [Color].
///
/// Returns [fallback] (which itself defaults to a neutral slate) when [hex] is
/// null, empty, or not a valid 6-digit hex value. Safe to call on user-supplied
/// data — does not throw.
Color hexToColor(String? hex, {Color? fallback}) {
  if (hex == null || hex.isEmpty) return fallback ?? const Color(0xFF475569);
  final cleaned = hex.replaceAll('#', '').trim();
  if (cleaned.length != 6) return fallback ?? const Color(0xFF475569);
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return fallback ?? const Color(0xFF475569);
  return Color(0xFF000000 | value);
}
