import '../../../data/models/budget_progress.dart';
import '../../../data/models/report_models.dart';

/// The on-device aggregation snapshot behind the AI Report screen.
///
/// Gathered by [aiReportDataProvider] (month-keyed, no AI/key needed) and
/// consumed by [AiReportNotifier._buildContext] →
/// [AiPayloadBuilder.buildReportContext], so the AI narrative is written from
/// the same figures the charts show. The charts themselves are now spec-driven
/// (see `lib/features/ai/dynamic_report/`): [SpecExecutor] resolves the
/// [DynamicReportSpec] via the same repositories, and [SpecChart] renders.
typedef AiReportData = ({
  MonthlySummary summary,
  List<BudgetProgress> budgets,
  List<MonthTotal> cashflow,
  List<CategoryTotal> topExpenseCategories,
  List<ModeTotal> modes,
});