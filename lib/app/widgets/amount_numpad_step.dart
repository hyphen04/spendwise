import 'package:flutter/material.dart';

import '../themes/app_fonts.dart';
import 'mono_numpad.dart';

/// Shared amount-entry primitives used by both the full amount-entry sheet and
/// the Home quick-add sheet, so the digit/backspace/parse rules stay identical
/// (the [MonoNumpad] widget itself is already shared — these are the string
/// math + the big amount display that wraps it).

/// Append a digit (or '.') to [raw] following the amount-entry rules:
/// only one decimal point, at most two decimal places, drop a leading '0'.
String appendDigit(String raw, String d) {
  if (d == '.') {
    if (raw.contains('.')) return raw;
    return raw.isEmpty ? '0.' : '$raw.';
  }
  final dotIdx = raw.indexOf('.');
  if (dotIdx != -1 && raw.length - dotIdx > 2) return raw;
  if (raw == '0') return d;
  return '$raw$d';
}

/// Remove the last character of [raw] (backspace). No-op when empty.
String backspaceDigit(String raw) =>
    raw.isEmpty ? raw : raw.substring(0, raw.length - 1);

/// Parse [raw] into a double, 0.0 when empty/unparseable.
double parseAmount(String raw) => double.tryParse(raw) ?? 0;

/// The big amount display: `₹` prefix + the raw digit string + an optional
/// backspace icon. Shared by every numpad-first sheet so the amount reads
/// identically everywhere.
class AmountDisplay extends StatelessWidget {
  const AmountDisplay({
    super.key,
    required this.raw,
    this.onBackspace,
    this.prefixSymbol = '₹',
    this.dimColor,
  });

  /// The current digit string (e.g. "1250.50"); shows '0' when empty.
  final String raw;
  final VoidCallback? onBackspace;
  final String prefixSymbol;

  /// Override for the dimmed prefix color (defaults to a faded onSurface via
  /// [onSurfaceVariant] when null — callers pass it for theme consistency).
  final Color? dimColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            prefixSymbol,
            style: plusJakartaSans(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: dimColor ?? cs.onSurface.withValues(alpha: 0.35),
              height: 1.0,
            ),
          ),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              raw.isEmpty ? '0' : raw,
              style: plusJakartaSans(
                fontSize: 52,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
                height: 1.0,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          if (raw.isNotEmpty)
            IconButton(
              onPressed: onBackspace,
              icon: const Icon(Icons.backspace_outlined),
              color: cs.onSurfaceVariant,
              tooltip: 'Delete last digit',
            ),
        ],
      ),
    );
  }
}