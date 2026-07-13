import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../data/repositories/recurring_repository.dart';
import 'database_provider.dart';
import 'reports_providers.dart';

final recurringRepositoryProvider = Provider<RecurringRepository>(
    (ref) => RecurringRepository(ref.watch(appDatabaseProvider)));

/// All recurring items, active first then by next due date (reactive).
final recurringItemsStreamProvider = StreamProvider<List<RecurringItem>>(
    (ref) => ref.watch(recurringRepositoryProvider).watchAll());

/// Active bills due within the next [horizonDays] days (default 3). Computed
/// on-device; used by the upcoming-bills surface and (later) the notification
/// scheduler. Reactive to recurring-item edits.
final upcomingBillsProvider =
    FutureProvider.family<List<RecurringItem>, int>((ref, horizonDays) async {
  ref.watch(recurringItemsStreamProvider);
  return ref.read(recurringRepositoryProvider).dueInDays(horizonDays);
});

/// Run recurring-payment detection over the last 12 months and seed any new
/// detected items (idempotent). Runs once per app session (a FutureProvider
/// caches its result); the Bills screen may re-trigger it with "Re-detect" by
/// invalidating this provider. Returns the number of newly inserted items.
final seedDetectedRecurringProvider = FutureProvider<int>((ref) async {
  return ref
      .read(recurringRepositoryProvider)
      .autoRefreshFromTransactions(ref.read(reportsRepositoryProvider));
});