import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/ai/services/weekly_digest_polish_controller.dart';
import '../features/digest/weekly_digest.dart';
import 'reports_providers.dart';

final weeklyDigestServiceProvider =
    Provider<WeeklyDigestService>((ref) =>
        WeeklyDigestService(ref.watch(reportsRepositoryProvider)));

/// The current weekly digest (on-device, no network). Recomputed when the
/// underlying transactions change.
final weeklyDigestProvider = FutureProvider<WeeklyDigest>(
    (ref) => ref.watch(weeklyDigestServiceProvider).compute());

/// On-demand LLM polish for the digest (opt-in via AI key). Falls back to the
/// deterministic digest text when AI is off / no key / any failure.
final weeklyDigestPolishProvider = StateNotifierProvider<
    WeeklyDigestPolishController, DigestPolishState>(
    (ref) => WeeklyDigestPolishController(ref));