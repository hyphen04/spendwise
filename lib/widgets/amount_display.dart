import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum AmountSignMode { none, auto, income, expense }

class AmountDisplay extends StatelessWidget {
  const AmountDisplay({
    super.key,
    required this.amount,
    this.color,
    this.fontSize = 52,
    this.prefix = '₹',
    this.fontWeight = FontWeight.w800,
    this.signMode = AmountSignMode.none,
  });

  final double amount;
  final Color? color;
  final double fontSize;
  final String prefix;
  final FontWeight fontWeight;

  /// How to prefix a +/− sign. In the monochrome theme this is the only cue
  /// distinguishing income from expense.
  final AmountSignMode signMode;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return Text(
      '${_sign()}$prefix${_fmt(amount.abs())}',
      style: GoogleFonts.manrope(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: c,
        fontFeatures: const [FontFeature.tabularFigures()],
        height: 1.0,
      ),
    );
  }

  String _sign() {
    switch (signMode) {
      case AmountSignMode.expense:
        return '−';
      case AmountSignMode.income:
        return '+';
      case AmountSignMode.auto:
        if (amount < 0) return '−';
        if (amount > 0) return '+';
        return '';
      case AmountSignMode.none:
        return '';
    }
  }

  static String _fmt(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }
}
