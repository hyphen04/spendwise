import '../../../data/db/app_database.dart';

/// Shared account→payment-mode auto-selection logic, extracted so both the
/// full amount-entry sheet and the Home quick-add sheet pick a mode
/// identically (no duplicated heuristics).
//
/// Convention (matches the original amount-entry sheet):
/// - A "cash"-type account (name contains "cash", case-insensitive) is forced
///   to the "Cash" payment mode.
/// - Any other account keeps an existing digital mode, or falls back to the
///   user's default mode / the first digital mode.

/// True when the account named [accountId] is a cash-type account.
bool isCashAccount(String? accountId, List<Account> accounts) {
  if (accountId == null) return false;
  final match = accounts.where((a) => a.id == accountId).firstOrNull;
  if (match == null) return false;
  return match.name.toLowerCase().contains('cash');
}

/// The "Cash" payment mode, or null if not seeded yet.
Mode? cashMode(List<Mode> modes) {
  final m = modes.where((m) => m.name.toLowerCase() == 'cash');
  return m.isEmpty ? null : m.first;
}

/// Modes visible for a non-cash account (excludes the "Cash" mode).
List<Mode> digitalModes(List<Mode> modes) =>
    modes.where((m) => m.name.toLowerCase() != 'cash').toList();

/// Resolve the mode for [accountId]:
/// - cash account → the cash mode id (or null if none seeded).
/// - other account → keep [currentModeId] when it's already a digital mode;
///   otherwise pick the user's [defaultModeId] when it's digital, else the
///   first digital mode, else null.
String? autoSelectMode({
  required String? accountId,
  required List<Account> accounts,
  required Mode? cashMode,
  required List<Mode> allModes,
  String? currentModeId,
  String? defaultModeId,
}) {
  if (isCashAccount(accountId, accounts)) return cashMode?.id;
  if (currentModeId != null && currentModeId != cashMode?.id) {
    // Keep an existing digital mode.
    final exists = allModes.any((m) => m.id == currentModeId);
    if (exists) return currentModeId;
  }
  final digital = digitalModes(allModes);
  if (defaultModeId != null && digital.any((m) => m.id == defaultModeId)) {
    return defaultModeId;
  }
  return digital.isNotEmpty ? digital.first.id : null;
}