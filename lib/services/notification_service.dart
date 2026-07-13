import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/bills_providers.dart';
import '../state/digest_providers.dart';

/// Schedules local notifications (bill-due reminders, the weekly digest).
///
/// **Status (Phase 5):** the *scheduling policy* lives here and is unit-safe,
/// but the OS-facing `flutter_local_notifications` plugin is **not yet wired** —
/// it needs Android channel + iOS permission setup that can't be verified in
/// a headless environment (see CLAUDE.md risk #5 and the iOS
/// `PERMISSION_<NAME>=1` Podfile-flag memory). Adding the plugin blind risks
/// breaking the build, so notifications are deliberately gated behind
/// [enabled]. Until the plugin is integrated, scheduled items are surfaced
/// in-app (Bills due badges, the digest preview screen) — the "what to say"
/// is already correct; only the "how to deliver to the OS" is pending.
///
/// When the plugin is added: implement [scheduleBillReminders] /
/// [scheduleWeeklyDigest] with the copy already computed below, and flip the
/// `enabled` default to follow a real notifications opt-in setting.
class NotificationService {
  NotificationService(this._ref);
  final Ref _ref;

  /// Whether OS notifications are configured. False until the plugin is wired.
  bool get enabled => false;

  /// Bills due within [horizonDays] (default 3) — the copy a notification would
  /// show. Observation tone, no alarm.
  Future<List<String>> upcomingBillReminders({int horizonDays = 3}) async {
    final items = await _ref
        .read(recurringRepositoryProvider)
        .dueInDays(horizonDays);
    return items.map((b) {
      final days = _ref
          .read(recurringRepositoryProvider)
          .daysUntilDue(b);
      final when = days == null
          ? 'soon'
          : days <= 0
              ? 'due today'
              : 'in $days day${days == 1 ? '' : 's'}';
      return 'Upcoming: ${b.name} ($when). No action needed — just a heads-up.';
    }).toList();
  }

  /// The weekly digest one-liner a notification would show.
  Future<String> weeklyDigestHeadline() async {
    final d = await _ref.read(weeklyDigestProvider.future);
    final head = d.spentThisWeek > 0
        ? 'You spent ₹${d.spentThisWeek.toStringAsFixed(0)} this week'
        : 'No spending logged yet this week';
    final delta = d.hasPriorWeek && d.deltaPct.isFinite
        ? ' (${d.deltaPct < 0 ? 'down' : 'up'} ${(d.deltaPct.abs() * 100).toStringAsFixed(0)}% vs last week)'
        : '';
    return '$head$delta. Tap to see the digest.';
  }

  // ── OS-facing hooks (no-ops until the plugin is wired) ──────────────────────

  Future<void> scheduleBillReminders({int horizonDays = 3}) async {
    if (!enabled) return;
    final reminders = await upcomingBillReminders(horizonDays: horizonDays);
    debugPrint('[NotificationService] would schedule ${reminders.length} '
        'bill reminders (plugin not yet wired).');
  }

  Future<void> scheduleWeeklyDigest() async {
    if (!enabled) return;
    final headline = await weeklyDigestHeadline();
    debugPrint('[NotificationService] would schedule weekly digest: $headline '
        '(plugin not yet wired).');
  }

  Future<void> cancelAll() async {
    if (!enabled) return;
    debugPrint('[NotificationService] cancelAll (plugin not yet wired).');
  }
}

final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService(ref));