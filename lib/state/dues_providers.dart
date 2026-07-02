import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/db/app_database.dart';
import '../data/db/daos/dues_dao.dart';
import '../data/repositories/dues_repository.dart';
import 'database_provider.dart';

final duesRepositoryProvider = Provider<DuesRepository>((ref) {
  return DuesRepository(ref.watch(appDatabaseProvider));
});

final dueContactsStreamProvider = StreamProvider<List<DueContact>>((ref) {
  return ref.watch(duesRepositoryProvider).watchAllContacts();
});

final unsettledEntriesProvider = StreamProvider.family<List<DueEntry>, String>((ref, contactId) {
  return ref.watch(duesRepositoryProvider).watchUnsettledEntries(contactId);
});

final contactSummaryProvider = FutureProvider.family<DueContactSummary, String>((ref, contactId) async {
  // Watch entries so it updates when they change
  ref.watch(unsettledEntriesProvider(contactId));
  return ref.watch(duesRepositoryProvider).getContactSummary(contactId);
});

final settlementsProvider = StreamProvider.family<List<DueSettlement>, String>((ref, contactId) {
  return ref.watch(duesRepositoryProvider).watchSettlements(contactId);
});

final settlementsWithCountProvider = StreamProvider.family<List<DueSettlementWithCount>, String>((ref, contactId) {
  return ref.watch(duesRepositoryProvider).watchSettlementsWithCount(contactId);
});

final settlementEntriesProvider = FutureProvider.family<List<DueEntry>, String>((ref, settlementId) async {
  return ref.watch(duesRepositoryProvider).getEntriesForSettlement(settlementId);
});

/// Returns a map of contactId -> balance. Positive = receivable, Negative = payable.
final allContactBalancesProvider = FutureProvider<Map<String, double>>((ref) async {
  // Watch all contacts and their entries to re-compute
  final contactsAsync = ref.watch(dueContactsStreamProvider);
  if (contactsAsync.valueOrNull == null) return {};
  
  // Re-run whenever ANY unsettled entries change for ANY contact
  for (final contact in contactsAsync.value!) {
    ref.watch(unsettledEntriesProvider(contact.id));
  }
  
  return ref.watch(duesRepositoryProvider).getAllContactBalances();
});

final totalPayableProvider = Provider<double>((ref) {
  final balancesAsync = ref.watch(allContactBalancesProvider);
  final balances = balancesAsync.valueOrNull ?? {};
  
  double total = 0;
  for (final b in balances.values) {
    if (b < 0) total += b.abs();
  }
  return total;
});

final totalReceivableProvider = Provider<double>((ref) {
  final balancesAsync = ref.watch(allContactBalancesProvider);
  final balances = balancesAsync.valueOrNull ?? {};
  
  double total = 0;
  for (final b in balances.values) {
    if (b > 0) total += b;
  }
  return total;
});

final monthlyVendorStatsProvider = FutureProvider.family<(int, double), ({String contactId, int year, int month})>((ref, args) {
  // Re-run when entries change for this contact
  ref.watch(unsettledEntriesProvider(args.contactId));
  ref.watch(settlementsProvider(args.contactId));
  
  return ref.watch(duesRepositoryProvider).getMonthlyVendorStats(
    args.contactId, 
    args.year, 
    args.month,
  );
});
