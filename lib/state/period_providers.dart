import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared period selected on the Home screen.
/// Other screens (e.g. Transactions "View all") can read/write this.
final selectedPeriodProvider =
    StateProvider<({int year, int month})>((_) {
  final now = DateTime.now();
  return (year: now.year, month: now.month);
});

/// One-shot navigation intent: Home's "View all" sets this; Transactions
/// consumes and clears it in the same frame.
final pendingTransactionsFilterProvider =
    StateProvider<({DateTime from, DateTime to})?>((_) => null);
