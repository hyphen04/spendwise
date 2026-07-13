import 'chart_spec.dart';

/// The built-in default report spec — the three charts the AI Report screen has
/// always shown (category donut, 6-month cashflow bars, budget progress),
/// expressed as specs. Used when AI is off, when `aiSpecEnabled` is off, or as
/// the graceful fallback when an LLM spec fails validation. Guarantees the
/// report is never empty and is spec-driven before any AI is wired in (Phase 1).
final DynamicReportSpec defaultReportSpec = DynamicReportSpec(
  charts: [
    ChartSpec(
      type: ChartType.pie,
      title: 'Where it went',
      provider: DataProvider.topCategories,
      params: const {'limit': 10},
    ),
    ChartSpec(
      type: ChartType.bar,
      title: 'Cashflow (6 months)',
      provider: DataProvider.cashflow6mo,
      params: const {'count': 6},
    ),
    ChartSpec(
      type: ChartType.progress,
      title: 'Budgets',
      provider: DataProvider.budgets,
      params: const {},
    ),
  ],
);