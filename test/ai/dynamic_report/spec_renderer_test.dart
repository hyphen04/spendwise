import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/ai/dynamic_report/chart_spec.dart';
import 'package:spendwise/features/ai/dynamic_report/spec_executor.dart';
import 'package:spendwise/features/ai/dynamic_report/spec_renderer.dart';

ChartSpec _spec(ChartType t, DataProvider p, {Map<String, Object> params = const {}}) =>
    ChartSpec(type: t, title: 't', provider: p, params: params);

ChartDataset _ds(List<Map<String, Object?>> rows, {DataProvider p = DataProvider.topCategories}) =>
    ChartDataset(rows, p);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('pie renders a PieChart from topCategories rows', (t) async {
    await t.pumpWidget(_wrap(SpecChart(
      spec: _spec(ChartType.pie, DataProvider.topCategories),
      dataset: _ds([
        {'name': 'Food', 'icon': '🍔', 'color': '16A34A', 'total': 500.0},
        {'name': 'Rent', 'icon': '🏠', 'color': 'DC2626', 'total': 1200.0},
      ]),
    )));
    expect(find.byType(PieChart), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
  });

  testWidgets('bar (cashflow6mo) renders grouped BarChart', (t) async {
    await t.pumpWidget(_wrap(SpecChart(
      spec: _spec(ChartType.bar, DataProvider.cashflow6mo, params: {'count': 6}),
      dataset: _ds([
        {'year': 2026, 'month': 4, 'income': 1000.0, 'expense': 600.0, 'net': 400.0},
        {'year': 2026, 'month': 5, 'income': 1000.0, 'expense': 800.0, 'net': 200.0},
      ], p: DataProvider.cashflow6mo),
    )));
    expect(find.byType(BarChart), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
  });

  testWidgets('bar (generic) renders a single-series BarChart', (t) async {
    await t.pumpWidget(_wrap(SpecChart(
      spec: _spec(ChartType.bar, DataProvider.modes),
      dataset: _ds([
        {'name': 'UPI', 'total': 300.0},
        {'name': 'Card', 'total': 200.0},
      ], p: DataProvider.modes),
    )));
    expect(find.byType(BarChart), findsOneWidget);
  });

  testWidgets('line renders a LineChart', (t) async {
    await t.pumpWidget(_wrap(SpecChart(
      spec: _spec(ChartType.line, DataProvider.cashflow6mo, params: {'count': 6}),
      dataset: _ds([
        {'year': 2026, 'month': 1, 'income': 100.0, 'expense': 50.0, 'net': 50.0},
        {'year': 2026, 'month': 2, 'income': 100.0, 'expense': 70.0, 'net': 30.0},
      ], p: DataProvider.cashflow6mo),
    )));
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('progress renders LinearProgressIndicator per row', (t) async {
    await t.pumpWidget(_wrap(SpecChart(
      spec: _spec(ChartType.progress, DataProvider.budgets),
      dataset: _ds([
        {'name': 'Food', 'spent': 400.0, 'effective': 500.0, 'fraction': 0.8, 'isOver': false},
      ], p: DataProvider.budgets),
    )));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
  });

  testWidgets('list renders ranked rows with names', (t) async {
    await t.pumpWidget(_wrap(SpecChart(
      spec: _spec(ChartType.list, DataProvider.modes),
      dataset: _ds([
        {'name': 'UPI', 'icon': '💳', 'total': 300.0},
        {'name': 'Cash', 'icon': '💵', 'total': 100.0},
      ], p: DataProvider.modes),
    )));
    expect(find.text('UPI'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
  });

  testWidgets('stat renders a large formatted amount', (t) async {
    await t.pumpWidget(_wrap(SpecChart(
      spec: ChartSpec(
        type: ChartType.stat,
        title: 'Net',
        provider: DataProvider.monthlySummary,
        series: const [ChartSeries(field: 'net')],
        caption: 'Income minus expense.',
      ),
      dataset: _ds([
        {'income': 1000.0, 'expense': 600.0, 'net': 400.0, 'opening': 0.0, 'closing': 400.0},
      ], p: DataProvider.monthlySummary),
    )));
    expect(find.textContaining('₹'), findsWidgets);
    expect(find.text('Income minus expense.'), findsOneWidget);
  });

  testWidgets('empty dataset → empty-state message, no chart', (t) async {
    await t.pumpWidget(_wrap(SpecChart(
      spec: _spec(ChartType.pie, DataProvider.topCategories),
      dataset: _ds(const [], p: DataProvider.topCategories),
    )));
    expect(find.byType(PieChart), findsNothing);
    expect(find.text('No spending recorded for this month.'), findsOneWidget);
  });

  testWidgets('error dataset → error message, no chart', (t) async {
    await t.pumpWidget(_wrap(SpecChart(
      spec: _spec(ChartType.pie, DataProvider.customSql),
      dataset: const ChartDataset([], DataProvider.customSql,
          error: 'Custom SQL is not enabled.'),
    )));
    expect(find.byType(PieChart), findsNothing);
    expect(find.text('Custom SQL is not enabled.'), findsOneWidget);
  });
}