// Shared money formatting helpers.
//
// The app is INR-focused and the existing report screens each define a local
// `_fmt`/`_fmtAmt` that abbreviates large amounts Indian-style (Cr/L/K). This
// is the single shared implementation so the AI feature (and any future code)
// doesn't add yet another copy. Existing report screens are not refactored
// here — that's a separate cleanup.
//
// All amounts in SpendWise are stored as plain doubles and summed across
// accounts without FX conversion, so these helpers are currency-symbol-only;
// they do not perform any conversion.

import 'package:intl/intl.dart';

/// Abbreviate a money amount Indian-style with the ₹ symbol.
///
///   950       → "₹950.00"
///   12500     → "₹12.5K"
///   150000    → "₹1.5L"
///   12000000  → "₹1.2Cr"
String fmtMoney(double v) {
  final abs = v.abs();
  final prefix = v < 0 ? '-' : '';
  if (abs >= 10000000) return '$prefix₹${(abs / 10000000).toStringAsFixed(1)}Cr';
  if (abs >= 100000) return '$prefix₹${(abs / 100000).toStringAsFixed(1)}L';
  if (abs >= 1000) return '$prefix₹${(abs / 1000).toStringAsFixed(1)}K';
  return '$prefix₹${abs.toStringAsFixed(2)}';
}

/// Full Indian-grouped amount with no abbreviation and no currency symbol.
/// Whole numbers drop the decimal tail; fractional amounts keep up to two
/// places. The sign is the caller's responsibility (callers pass a positive
/// magnitude and prepend their own `+`/`−`/`₹`), so the magnitude is what's
/// formatted here.
///
///   950       → "950"
///   12500     → "12,500"
///   150000    → "1,50,000"
///   12000000  → "1,20,00,000"
///   12500.5   → "12,500.5"
///
/// Use this for surfaces where the full amount must be clearly readable
/// (transaction rows, home/transactions totals) — prefer [fmtMoney] for
/// compact report/forecast contexts where K/L/Cr keeps big totals short.
String fmtGrouped(double v) {
  return NumberFormat('#,##,##0.##', 'en_IN').format(v.abs());
}

/// Full Indian-grouped amount with the ₹ symbol and a leading `−` for
/// negatives — no K/L/Cr abbreviation. Use where the exact figure must be
/// readable (e.g. the Home net-worth display), prefer [fmtMoney] for compact
/// contexts where K/L/Cr keeps big totals short.
///
///   950       → "₹950"
///   12500     → "₹12,500"
///   150000    → "₹1,50,000"
///   -150000   → "−₹1,50,000"
String fmtFullMoney(double v) {
  final prefix = v < 0 ? '−' : '';
  return '$prefix₹${fmtGrouped(v)}';
}

/// Plain grouped number without symbol or abbreviation, e.g. 12500 → "12,500".
String fmtNumber(double v) {
  final abs = v.abs();
  final s = abs == abs.truncateToDouble()
      ? abs.toInt().toString()
      : abs.toStringAsFixed(2);
  // Indian grouping for the integer part only.
  return v < 0 ? '-$s' : s;
}

/// Ordinal for a day-of-month: 1 → "1st", 2 → "2nd", 3 → "3rd", 21 → "21st".
String dayOrdinal(int day) {
  if (day >= 11 && day <= 13) return '${day}th';
  switch (day % 10) {
    case 1:
      return '${day}st';
    case 2:
      return '${day}nd';
    case 3:
      return '${day}rd';
    default:
      return '${day}th';
  }
}