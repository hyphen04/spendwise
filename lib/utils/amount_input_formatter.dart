import 'package:flutter/services.dart';

/// Limits [TextField] input to a monetary amount shape: digits, at most one
/// '.', and at most two fractional digits. Rejected edits return the old
/// value, so the field stays parseable.
class AmountInputFormatter extends TextInputFormatter {
  const AmountInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    // Digits and at most one '.'
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(text)) return oldValue;
    // At most 2 fractional digits
    final dot = text.indexOf('.');
    if (dot != -1 && text.length - dot - 1 > 2) return oldValue;
    return newValue;
  }
}

/// Shared list to drop on any amount `TextFormField` / `TextField`.
const List<TextInputFormatter> amountInputFormatters = [AmountInputFormatter()];
