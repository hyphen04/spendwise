import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../data/repositories/goals_repository.dart';
import 'database_provider.dart';

final goalsRepositoryProvider = Provider<GoalsRepository>(
    (ref) => GoalsRepository(ref.watch(appDatabaseProvider)));

/// All goals, active first then by target date (reactive).
final goalsStreamProvider = StreamProvider<List<Goal>>(
    (ref) => ref.watch(goalsRepositoryProvider).watchAll());

/// Reactive progress snapshots for every goal.
final goalsProgressProvider = Provider<List<GoalProgress>>((ref) {
  final goals = ref.watch(goalsStreamProvider).valueOrNull ?? const <Goal>[];
  return ref.read(goalsRepositoryProvider).progressAll(goals);
});