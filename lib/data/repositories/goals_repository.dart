import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';

/// Read-only progress snapshot for a [Goal], computed on-device.
class GoalProgress {
  GoalProgress({
    required this.goal,
    required this.saved,
    required this.target,
    required this.fraction,
    required this.remaining,
  });

  final Goal goal;
  final double saved;
  final double target;
  final double fraction; // 0..1 (clamped; can exceed 1 if over-saved)
  final double remaining; // target - saved (>= 0)

  bool get isComplete => remaining <= 0;

  /// Months remaining until [goal.targetDate] from today (>= 0). Null when no
  /// target date or it has already passed.
  int? get monthsLeft {
    final d = DateTime.tryParse(goal.targetDate ?? '');
    if (d == null) return null;
    final today = DateTime.now();
    final date = DateTime(d.year, d.month, d.day);
    if (!date.isAfter(DateTime(today.year, today.month, today.day))) return 0;
    final months =
        (date.year - today.year) * 12 + (date.month - today.month);
    return months < 0 ? 0 : months;
  }

  ///₹/month needed to hit the target by the deadline (observation, not a
  /// demand). Null when no deadline or already complete.
  double? get requiredPerMonth {
    final m = monthsLeft;
    if (m == null || m <= 0) return null;
    if (remaining <= 0) return 0;
    return remaining / m;
  }
}

/// Repository for savings [Goal]s. CRUD + progress + contributions. All data
/// is the user's own and stays on-device; this table is never sent to the AI.
class GoalsRepository {
  GoalsRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<Goal>> watchAll() => _db.goalsDao.watchAll();
  Future<List<Goal>> getAll() => _db.goalsDao.getAll();
  Future<Goal?> getById(String id) => _db.goalsDao.getById(id);

  Future<void> create({
    required String name,
    required double targetAmount,
    String icon = '🎯',
    String color = '#2563EB',
    double savedAmount = 0,
    DateTime? targetDate,
    String? linkedAccountId,
    double? monthlyCommitment,
    bool isActive = true,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.goalsDao.upsert(GoalsCompanion.insert(
      id: _uuid.v4(),
      name: name,
      icon: Value(icon),
      color: Value(color),
      targetAmount: targetAmount,
      savedAmount: Value(savedAmount),
      targetDate: Value(targetDate != null
          ? DateTime(targetDate.year, targetDate.month, targetDate.day)
              .toIso8601String()
              .substring(0, 10)
          : null),
      linkedAccountId: Value(linkedAccountId),
      monthlyCommitment: Value(monthlyCommitment),
      isActive: Value(isActive),
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<void> update(
    Goal existing, {
    required String name,
    required double targetAmount,
    String? icon,
    String? color,
    double? savedAmount,
    DateTime? targetDate,
    String? linkedAccountId,
    double? monthlyCommitment,
    bool? isActive,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.goalsDao.upsert(GoalsCompanion(
      id: Value(existing.id),
      name: Value(name),
      icon: Value(icon ?? existing.icon),
      color: Value(color ?? existing.color),
      targetAmount: Value(targetAmount),
      savedAmount: Value(savedAmount ?? existing.savedAmount),
      targetDate: Value(targetDate != null
          ? DateTime(targetDate.year, targetDate.month, targetDate.day)
              .toIso8601String()
              .substring(0, 10)
          : existing.targetDate),
      linkedAccountId: Value(linkedAccountId),
      monthlyCommitment: Value(monthlyCommitment),
      isActive: Value(isActive ?? existing.isActive),
      createdAt: Value(existing.createdAt),
      updatedAt: Value(now),
    ));
  }

  /// Add a contribution (₹) to a goal's saved amount. A negative amount is
  /// allowed (withdrawal/adjustment) since the user owns this number; we only
  /// guard against NaN/non-finite.
  Future<void> contribute(Goal existing, double amount) {
    if (amount.isNaN || amount.isInfinite) return Future.value();
    final next = (existing.savedAmount + amount).clamp(0.0, double.infinity);
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.goalsDao.upsert(GoalsCompanion(
      id: Value(existing.id),
      name: Value(existing.name),
      icon: Value(existing.icon),
      color: Value(existing.color),
      targetAmount: Value(existing.targetAmount),
      savedAmount: Value(next),
      targetDate: Value(existing.targetDate),
      linkedAccountId: Value(existing.linkedAccountId),
      monthlyCommitment: Value(existing.monthlyCommitment),
      isActive: Value(existing.isActive),
      createdAt: Value(existing.createdAt),
      updatedAt: Value(now),
    ));
  }

  Future<int> delete(String id) => _db.goalsDao.deleteById(id);

  /// On-device progress snapshot for a single goal.
  GoalProgress progressFor(Goal g) {
    final target = g.targetAmount;
    final saved = g.savedAmount;
    final remaining = (target - saved).clamp(0.0, double.infinity);
    return GoalProgress(
      goal: g,
      saved: saved,
      target: target,
      fraction: target > 0 ? saved / target : 0.0,
      remaining: remaining,
    );
  }

  List<GoalProgress> progressAll(List<Goal> goals) =>
      goals.map(progressFor).toList();
}