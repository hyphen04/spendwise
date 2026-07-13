import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/forecast/cashflow_forecast.dart';
import '../features/forecast/run_rate.dart';
import 'bills_providers.dart';
import 'reports_providers.dart';

export '../features/forecast/cashflow_forecast.dart' show ForecastMode;

/// Shared selection of the forecast period (Home glance card + Forecast
/// report stay in sync via this).
final forecastModeProvider =
    StateProvider<ForecastMode>((ref) => ForecastMode.monthly);

final runRateServiceProvider =
    Provider<RunRateService>((ref) => RunRateService(ref.watch(reportsRepositoryProvider)));

/// Top run-rate observations for the current month (no-shame).
final runRateObservationsProvider = FutureProvider<List<RunRateObservation>>(
    (ref) => ref.watch(runRateServiceProvider).topObservations());

final cashflowForecastServiceProvider = Provider<CashflowForecastService>(
    (ref) => CashflowForecastService(
          ref.watch(reportsRepositoryProvider),
          ref.watch(recurringRepositoryProvider),
        ));

/// Current month's end-of-month projection (spend run-rated; income as-is).
final cashflowMonthlyForecastProvider = FutureProvider<CashflowForecast>(
    (ref) => ref.watch(cashflowForecastServiceProvider).computeMonthly());

/// Rolling 6-month projection (now + 6 × avg monthly net over last 6 months).
final cashflowSixMonthForecastProvider = FutureProvider<CashflowForecast>(
    (ref) => ref.watch(cashflowForecastServiceProvider).computeSixMonths());

/// The forecast for the currently selected [ForecastMode].
final cashflowForecastForModeProvider =
    FutureProvider.family<CashflowForecast, ForecastMode>((ref, mode) async {
  if (mode == ForecastMode.sixMonths) {
    return ref.watch(cashflowSixMonthForecastProvider.future);
  }
  return ref.watch(cashflowMonthlyForecastProvider.future);
});

/// Back-compat: the current month's forecast. Prefer
/// [cashflowForecastForModeProvider].
final cashflowForecastProvider = cashflowMonthlyForecastProvider;

/// Per-day expense totals for the day-grid heatmap, keyed "yyyy-MM-dd".
/// One grouped query for the whole visible window.
final forecastDayExpenseProvider =
    FutureProvider.family<Map<String, double>, ForecastMode>((ref, mode) async {
  final repo = ref.watch(reportsRepositoryProvider);
  final now = DateTime.now();
  if (mode == ForecastMode.sixMonths) {
    // Rolling 6 calendar months: first day of (current month − 5) → end of
    // current month (so the current month's remaining days show faint).
    final start = DateTime(now.year, now.month - 5, 1);
    final from = start.toIso8601String();
    final to = DateTime(now.year, now.month + 1, 1).toIso8601String();
    return repo.dailyExpenseByDay(from: from, to: to);
  }
  final from = DateTime(now.year, now.month).toIso8601String();
  final to = DateTime(now.year, now.month + 1).toIso8601String();
  return repo.dailyExpenseByDay(from: from, to: to);
});