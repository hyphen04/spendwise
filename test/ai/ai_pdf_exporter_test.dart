import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/ai/dynamic_report/chart_spec.dart';
import 'package:spendwise/features/ai/dynamic_report/spec_executor.dart';
import 'package:spendwise/features/ai/services/ai_pdf_exporter.dart';

void main() {
  group('AiPdfExporter.buildPdfBytes', () {
    test('produces a valid non-empty PDF with charts + summary', () async {
      final spec = DynamicReportSpec(
        charts: [
          ChartSpec(
            type: ChartType.pie,
            title: 'Where it went',
            provider: DataProvider.topCategories,
            caption: 'Top categories this month.',
          ),
          ChartSpec(
            type: ChartType.progress,
            title: 'Budgets',
            provider: DataProvider.budgets,
          ),
        ],
      );
      final datasets = <ChartDataset>[
        ChartDataset(
          [
            {'name': 'Food & Dining', 'icon': '🍔', 'color': '#059669', 'total': 12000},
            {'name': 'Home Rent', 'icon': '🏠', 'color': '#2563eb', 'total': 8000},
          ],
          DataProvider.topCategories,
        ),
        ChartDataset(
          [
            {'name': 'Food', 'icon': '🍔', 'color': '#059669', 'spent': 12000,
             'effective': 10000, 'fraction': 1.0, 'isOver': true},
            {'name': 'Rent', 'icon': '🏠', 'color': '#2563eb', 'spent': 8000,
             'effective': 8000, 'fraction': 1.0, 'isOver': false},
          ],
          DataProvider.budgets,
        ),
        ChartDataset(
          [
            {'income': 60000, 'expense': 45000, 'net': 15000,
             'opening': 10000, 'closing': 25000},
          ],
          DataProvider.monthlySummary,
        ),
      ];
      final markdown = '# Monthly review\n\nYou spent most on {{chart:0}}.\n\n'
          'Budgets are tight: {{chart:1}}.';

      final bytes = await AiPdfExporter.buildPdfBytes(
        markdown: markdown,
        periodLabel: 'July 2026',
        spec: spec,
        datasets: datasets,
        title: 'SpendWise — AI Report',
        flagged: false,
      );

      expect(bytes, isNotEmpty);
      // A PDF starts with the %PDF- header magic.
      expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
      // Substantial content (charts + summary + narrative), well over a bare stub.
      expect(bytes.length, greaterThan(2000));
    });

    test('handles empty / error datasets without throwing', () async {
      final spec = DynamicReportSpec(
        charts: [
          ChartSpec(type: ChartType.bar, title: 'Cashflow', provider: DataProvider.cashflow6mo),
          ChartSpec(type: ChartType.list, title: 'Modes', provider: DataProvider.modes),
        ],
      );
      final datasets = <ChartDataset>[
        ChartDataset(const [], DataProvider.cashflow6mo),
        ChartDataset(const [], DataProvider.modes, error: 'no data'),
      ];

      final bytes = await AiPdfExporter.buildPdfBytes(
        markdown: 'No charts referenced.',
        periodLabel: 'July 2026',
        spec: spec,
        datasets: datasets,
        flagged: true,
        issues: const ['AI used an unknown label: cat_9'],
      );

      expect(bytes, isNotEmpty);
      expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
    });

    test('generic table fallback renders customSql rows', () async {
      final spec = DynamicReportSpec(
        charts: [
          ChartSpec(type: ChartType.list, title: 'Custom', provider: DataProvider.customSql),
        ],
      );
      final datasets = <ChartDataset>[
        ChartDataset(
          [
            {'label': 'Row A', 'amount': 100},
            {'label': 'Row B', 'amount': 200},
          ],
          DataProvider.customSql,
        ),
      ];

      final bytes = await AiPdfExporter.buildPdfBytes(
        markdown: 'See {{chart:0}}.',
        periodLabel: 'July 2026',
        spec: spec,
        datasets: datasets,
      );

      expect(bytes, isNotEmpty);
      expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
    });
  });
}