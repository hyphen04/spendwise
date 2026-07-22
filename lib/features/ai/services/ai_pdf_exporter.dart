import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../app/utils/money_format.dart';
import '../dynamic_report/chart_spec.dart';
import '../dynamic_report/spec_executor.dart';

/// Renders an AI-generated narrative report (a Markdown string constrained to
/// the `ChangelogMarkdown` subset) into a shareable PDF — **with** the report's
/// on-device charts, a monthly-summary stat row, the gatekeeper "Checked
/// on-device" note, and a real title.
///
/// Charts are rebuilt natively with `pw` primitives (NOT rasterized fl_chart):
/// the screen's `SpecChart`s live inside a `ListView` and may be lazily
/// disposed at export time, and fl_chart animates on first build, so an
/// off-screen `RepaintBoundary.toImage` capture is fragile. Native rendering
/// is deterministic and font-safe. Emoji icons are deliberately NOT rendered
/// (the default `pdf` font lacks emoji glyphs → blank boxes); a colored
/// swatch from each row's `color` hex replaces them.
///
/// The Markdown→`pw` mapping mirrors `ChangelogMarkdown`'s supported subset:
/// `#`–`####` headings, `-`/`*` bullets (one nesting level), numbered lists,
/// `>` blockquotes, `---` rules, and inline `**bold**` / `` `code`` /
/// `[text](url)`. Anything else degrades to plain text so the PDF never shows
/// literal markers.
class AiPdfExporter {
  AiPdfExporter._();

  /// Build the PDF for [markdown] covering [periodLabel], interleaving the
  /// spec's [charts]/[datasets] at `{{chart:N}}` markers (and appending any the
  /// narrative didn't reference), a monthly-summary stat row when available,
  /// and the gatekeeper note. Returns the written file's path.
  static Future<String> export({
    required String markdown,
    required String periodLabel,
    required DynamicReportSpec spec,
    required List<ChartDataset> datasets,
    String title = 'SpendWise — AI Report',
    bool flagged = false,
    List<String> issues = const [],
  }) async {
    final font = await _loadDefaultFont();
    final bytes = await buildPdfBytes(
      markdown: markdown,
      periodLabel: periodLabel,
      spec: spec,
      datasets: datasets,
      title: title,
      flagged: flagged,
      issues: issues,
      font: font,
    );
    final dir = await getTemporaryDirectory();
    final stamp =
        DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '');
    final file = File('${dir.path}/spendwise_ai_report_$stamp.pdf');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Loads the bundled Plus Jakarta Sans TTF as the PDF's default font, so
  /// `₹`, em dash, and bullet glyphs render (the `pdf` package's default
  /// Helvetica has no Unicode support). Returns null on any failure so the
  /// caller falls back to Helvetica gracefully — the PDF still generates.
  static Future<pw.Font?> _loadDefaultFont() async {
    try {
      final data = await rootBundle.load('assets/fonts/PlusJakartaSans.ttf');
      return pw.Font.ttf(data);
    } catch (_) {
      return null;
    }
  }

  /// Builds the PDF bytes only (no file IO) — exposed for tests so they don't
  /// need the `path_provider` platform channel. [font] is the default font;
  /// null falls back to Helvetica (no Unicode coverage, but fine for
  /// structural tests).
  @visibleForTesting
  static Future<Uint8List> buildPdfBytes({
    required String markdown,
    required String periodLabel,
    required DynamicReportSpec spec,
    required List<ChartDataset> datasets,
    String title = 'SpendWise — AI Report',
    bool flagged = false,
    List<String> issues = const [],
    pw.Font? font,
  }) async {
    final theme = font == null
        ? null
        : pw.ThemeData.withFont(
            base: font, bold: font, italic: font, boldItalic: font);
    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) => _buildBody(
          markdown: markdown,
          periodLabel: periodLabel,
          spec: spec,
          datasets: datasets,
          title: title,
          flagged: flagged,
          issues: issues,
        ),
      ),
    );
    return doc.save();
  }

  // ── Body assembly ────────────────────────────────────────────────────────

  static final double _contentWidth =
      PdfPageFormat.a4.width - 64; // A4 portrait minus 32px margins.

  static List<pw.Widget> _buildBody({
    required String markdown,
    required String periodLabel,
    required DynamicReportSpec spec,
    required List<ChartDataset> datasets,
    required String title,
    required bool flagged,
    required List<String> issues,
  }) {
    final widgets = <pw.Widget>[];

    // 1) Header.
    widgets.add(pw.Text(
      title,
      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
    ));
    widgets.add(pw.SizedBox(height: 4));
    widgets.add(pw.Text(
      'Period: $periodLabel',
      style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
    ));
    widgets.add(pw.SizedBox(height: 14));

    // 2) Monthly summary stat row (only if a monthlySummary dataset exists).
    final summary = _findSummary(datasets);
    if (summary != null) {
      widgets.add(_summaryRow(summary));
      widgets.add(pw.SizedBox(height: 14));
    }

    // 3) Narrative interleaved with charts + unreferenced charts appended.
    widgets.addAll(_renderDocument(markdown, spec, datasets));

    // 4) Gatekeeper note.
    widgets.add(pw.SizedBox(height: 16));
    widgets.add(_gatekeeperNote(flagged, issues));

    // 5) Footer.
    widgets.add(pw.SizedBox(height: 18));
    widgets.add(pw.Text(
      'Generated on '
      '${DateTime.now().toIso8601String().substring(0, 16).replaceAll('T', ' ')} '
      '· SpendWise AI Copilot',
      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
    ));
    return widgets;
  }

  static ChartDataset? _findSummary(List<ChartDataset> datasets) {
    for (final d in datasets) {
      if (d.provider == DataProvider.monthlySummary && !d.hasError && !d.isEmpty) {
        return d;
      }
    }
    return null;
  }

  /// Render the monthly-summary row as stat cells (Income / Expense / Net /
  /// Closing). Row shape: `{income, expense, net, opening, closing}`.
  static pw.Widget _summaryRow(ChartDataset ds) {
    final row = ds.rows.first;
    final cells = <_StatCell>[
      _StatCell('Income', _num(row['income'])),
      _StatCell('Expense', _num(row['expense'])),
      _StatCell('Net', _num(row['net'])),
      _StatCell('Closing', _num(row['closing'])),
    ];
    final cellWidth = _contentWidth / cells.length;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final c in cells)
          pw.SizedBox(
            width: cellWidth,
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    c.label.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey600,
                      letterSpacing: 0.6,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    fmtMoney(c.value),
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: c.label == 'Net'
                          ? (c.value < 0 ? PdfColors.red700 : PdfColors.green700)
                          : PdfColors.grey900,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Splits the markdown on `{{chart:N}}` markers into text segments and inline
  /// chart blocks, then appends charts the narrative didn't reference. Mirrors
  /// `ai_report_screen._reportDocument` so the PDF matches the on-screen
  /// layout.
  static List<pw.Widget> _renderDocument(
      String markdown, DynamicReportSpec spec, List<ChartDataset> datasets) {
    final chartCount = spec.charts.length;
    final re = RegExp(r'\{\{chart:(\d+)\}\}');
    final segments = <_Segment>[];
    var last = 0;
    for (final m in re.allMatches(markdown)) {
      if (m.start > last) segments.add(_Segment.text(markdown.substring(last, m.start)));
      final idx = int.tryParse(m.group(1)!) ?? -1;
      if (idx >= 0 && idx < chartCount) segments.add(_Segment.chart(idx));
      last = m.end;
    }
    if (last < markdown.length) segments.add(_Segment.text(markdown.substring(last)));

    final referenced = <int>{
      for (final s in segments)
        if (s.isChart) s.chartIndex!,
    };
    final unreferenced = [
      for (var i = 0; i < chartCount; i++) if (!referenced.contains(i)) i,
    ];

    final widgets = <pw.Widget>[];
    for (final seg in segments) {
      if (seg.isChart) {
        widgets.addAll(_renderChart(spec, datasets, seg.chartIndex!));
      } else {
        final t = seg.text ?? '';
        if (t.trim().isNotEmpty) widgets.addAll(_renderMarkdown(t));
      }
    }
    for (final i in unreferenced) {
      widgets.addAll(_renderChart(spec, datasets, i));
    }
    return widgets;
  }

  /// One chart: title → native visualization → optional caption. Empty/error
  /// datasets render a quiet "no data" line so the chart's title still anchors
  /// the section.
  static List<pw.Widget> _renderChart(
      DynamicReportSpec spec, List<ChartDataset> datasets, int index) {
    if (index >= datasets.length) return const [];
    final chartSpec = spec.charts[index];
    final dataset = datasets[index];
    final out = <pw.Widget>[];

    out.add(pw.SizedBox(height: 8));
    out.add(pw.Text(
      chartSpec.title,
      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
    ));
    out.add(pw.SizedBox(height: 6));

    if (dataset.hasError) {
      out.add(_muted('Could not load this chart.'));
    } else if (dataset.isEmpty) {
      out.add(_muted('No data for this chart.'));
    } else {
      out.add(_chartViz(chartSpec, dataset));
    }

    if (chartSpec.caption != null && chartSpec.caption!.trim().isNotEmpty) {
      out.add(pw.SizedBox(height: 4));
      out.add(pw.Text(
        chartSpec.caption!,
        style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic, color: PdfColors.grey600),
      ));
    }
    return out;
  }

  static pw.Widget _chartViz(ChartSpec spec, ChartDataset dataset) {
    switch (spec.type) {
      case ChartType.pie:
        return _pieViz(dataset.rows);
      case ChartType.progress:
        return _progressViz(dataset.rows);
      case ChartType.bar:
      case ChartType.line:
        return _cashflowViz(dataset.rows);
      case ChartType.list:
      case ChartType.stat:
        return _genericTable(dataset.rows);
    }
  }

  // ── Chart visualizations ─────────────────────────────────────────────────

  /// Pie (topCategories) → horizontal bar list. Row shape: {name, icon, color,
  /// total}. Emoji `icon` is intentionally dropped; a colored swatch replaces
  /// it (the default `pdf` font has no emoji glyphs).
  static pw.Widget _pieViz(List<Map<String, Object?>> rows) {
    final maxTotal = rows
        .map((r) => _num(r['total']))
        .fold<double>(0, (a, b) => a > b ? a : b);
    final col = <pw.Widget>[];
    for (final r in rows) {
      final name = (r['name'] ?? '').toString();
      final total = _num(r['total']);
      final color = _pdfColor(r['color']);
      final fraction = maxTotal > 0 ? (total / maxTotal).clamp(0.0, 1.0) : 0.0;
      col.add(pw.Row(
        children: [
          _swatch(color),
          pw.SizedBox(width: 6),
          pw.Expanded(child: pw.Text(name, style: const pw.TextStyle(fontSize: 10))),
          pw.SizedBox(width: 8),
          pw.Text(
            fmtMoney(total),
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ));
      col.add(pw.SizedBox(height: 3));
      col.add(_bar(fraction, color));
      col.add(pw.SizedBox(height: 10));
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: col,
    );
  }

  /// Progress (budgets) → per-budget bar. Row shape: {name, icon, color, spent,
  /// effective, fraction, isOver}.
  static pw.Widget _progressViz(List<Map<String, Object?>> rows) {
    final col = <pw.Widget>[];
    for (final r in rows) {
      final name = (r['name'] ?? '').toString();
      final spent = _num(r['spent']);
      final effective = _num(r['effective']);
      final fraction = _num(r['fraction']).clamp(0.0, 1.0);
      final isOver = r['isOver'] == true;
      final color = isOver ? PdfColors.red600 : _pdfColor(r['color']);
      col.add(pw.Row(
        children: [
          _swatch(color),
          pw.SizedBox(width: 6),
          pw.Expanded(child: pw.Text(name, style: const pw.TextStyle(fontSize: 10))),
          pw.SizedBox(width: 8),
          pw.Text(
            '${fmtMoney(spent)} / ${fmtMoney(effective)}',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: isOver ? PdfColors.red700 : PdfColors.grey900,
            ),
          ),
        ],
      ));
      col.add(pw.SizedBox(height: 3));
      col.add(_bar(fraction, color));
      col.add(pw.SizedBox(height: 10));
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: col,
    );
  }

  /// Bar/line (cashflow6mo) → table Month | Income | Expense | Net. Row shape:
  /// {year, month, income, expense, net}. Falls back to a generic table when
  /// rows don't carry those fields.
  static pw.Widget _cashflowViz(List<Map<String, Object?>> rows) {
    final isCashflow = rows.isNotEmpty &&
        rows.first.containsKey('income') &&
        rows.first.containsKey('expense');
    if (!isCashflow) return _genericTable(rows);

    const monthW = 150.0;
    const numW = 110.0;
    final header = _tableRow(
      ['Month', 'Income', 'Expense', 'Net'],
      [monthW, numW, numW, numW],
      header: true,
    );
    final dataRows = <pw.Widget>[];
    for (final r in rows) {
      final income = _num(r['income']);
      final expense = _num(r['expense']);
      final net = _num(r['net']);
      final monthLabel = _monthLabel(r['year'], r['month']);
      dataRows.add(_tableRow(
        [monthLabel, fmtMoney(income), fmtMoney(expense), fmtMoney(net)],
        [monthW, numW, numW, numW],
        netColor: net < 0 ? PdfColors.red700 : PdfColors.green700,
      ));
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [header, pw.Divider(color: PdfColors.grey400, thickness: 0.6), ...dataRows],
    );
  }

  /// Generic table: columns = union of row keys (first-seen order), cells
  /// stringified. Used for `list` / `stat` / `customSql` / unknown shapes.
  static pw.Widget _genericTable(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return _muted('No data.');
    final keys = <String>[];
    for (final r in rows) {
      for (final k in r.keys) {
        if (!keys.contains(k)) keys.add(k);
      }
    }
    if (keys.isEmpty) return _muted('No data.');
    final colW = _contentWidth / keys.length;
    final widths = List<double>.filled(keys.length, colW);
    final header = _tableRow(keys, widths, header: true);
    final dataRows = <pw.Widget>[];
    for (final r in rows) {
      dataRows.add(_tableRow(
        [for (final k in keys) _cellString(r[k])],
        widths,
      ));
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [header, pw.Divider(color: PdfColors.grey400, thickness: 0.6), ...dataRows],
    );
  }

  // ── Small building blocks ─────────────────────────────────────────────────

  static pw.Widget _swatch(PdfColor color) {
    return pw.Container(
      width: 9,
      height: 9,
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
      ),
    );
  }

  /// A horizontal progress bar: filled `fraction` of the track in [color], the
  /// remainder in a light track color. Fixed track width = content width.
  static pw.Widget _bar(double fraction, PdfColor color) {
    final fill = (fraction * _contentWidth).clamp(0.0, _contentWidth);
    final rest = (_contentWidth - fill).clamp(0.0, _contentWidth);
    return pw.Row(
      children: [
        pw.Container(width: fill, height: 6, color: color),
        pw.Container(width: rest, height: 6, color: PdfColors.grey200),
      ],
    );
  }

  static pw.Widget _tableRow(
    List<String> cells,
    List<double> widths, {
    bool header = false,
    PdfColor? netColor,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < cells.length; i++)
          pw.SizedBox(
            width: widths[i],
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
              child: pw.Text(
                cells[i],
                style: pw.TextStyle(
                  fontSize: header ? 9 : 10,
                  fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: (i == 3 && netColor != null) ? netColor : PdfColors.grey900,
                ),
              ),
            ),
          ),
      ],
    );
  }

  static pw.Widget _muted(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 2),
        child: pw.Text(text, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
      );

  static pw.Widget _gatekeeperNote(bool flagged, List<String> issues) {
    if (!flagged) {
      // The pdf package's default font has no glyph font loaded for icons, so
      // render the note as plain text (no checkmark icon) to stay font-safe.
      return pw.Text('Checked on-device',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600));
    }
    final note = issues.isEmpty
        ? 'Checked on-device · flagged'
        : 'Checked on-device · flagged (${issues.length})';
    final col = <pw.Widget>[
      pw.Text(note, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.amber800)),
    ];
    for (final issue in issues.take(4)) {
      col.add(pw.Text('  • $issue', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)));
    }
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: col);
  }

  // ── Markdown → pw.Widgets ─────────────────────────────────────────────────

  static final RegExp _hrRe = RegExp(r'^\s*(-{3,}|\*{3,}|_{3,})\s*$');
  static final RegExp _numberedRe = RegExp(r'^(\s*)(\d{1,3})\.\s+(.*)$');
  static final RegExp _bulletRe = RegExp(r'^(\s*)(?:[-*])\s+(.*)$');

  static final RegExp _inlineRe = RegExp(
    r'\*\*(.+?)\*\*' // 1: bold
    r'|\[([^\]]+)\]\(([^)]+)\)' // 2: link text, 3: link url
    r'|`([^`]+)`', // 4: code
  );

  static List<pw.Widget> _renderMarkdown(String src) {
    final lines = src.replaceAll('\r\n', '\n').split('\n');
    final blocks = <pw.Widget>[];

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        blocks.add(pw.SizedBox(height: 6));
        continue;
      }
      if (_hrRe.hasMatch(line)) {
        blocks.add(pw.Divider(color: PdfColors.grey400, thickness: 0.6));
        blocks.add(pw.SizedBox(height: 6));
        continue;
      }
      final level = _headingLevel(line);
      if (level > 0) {
        blocks.add(_heading(line.substring(level + 1).trim(), level));
        blocks.add(pw.SizedBox(height: 4));
        continue;
      }
      if (line.startsWith('>')) {
        blocks.add(_blockquote(line.replaceFirst(RegExp(r'^>\s?'), '')));
        continue;
      }
      final numbered = _numberedRe.firstMatch(line);
      if (numbered != null) {
        final indent = (numbered.group(1)!.length ~/ 2).clamp(0, 1);
        blocks.add(_listItem(
          '${numbered.group(2)}.',
          numbered.group(3)!,
          indent,
        ));
        continue;
      }
      final bullet = _bulletRe.firstMatch(line);
      if (bullet != null) {
        final indent = (bullet.group(1)!.length ~/ 2).clamp(0, 1);
        // Nested level uses · (U+00B7) instead of the white-bullet ◦ (U+25E6),
        // which the bundled font doesn't cover.
        blocks.add(_listItem(indent == 0 ? '•' : '·', bullet.group(2)!, indent));
        continue;
      }
      blocks.add(_paragraph(line));
      blocks.add(pw.SizedBox(height: 2));
    }
    return blocks;
  }

  static int _headingLevel(String line) {
    var level = 0;
    while (level < line.length && line[level] == '#') {
      level++;
    }
    if (level >= 1 && level <= 4 && line.length > level && line[level] == ' ') {
      return level;
    }
    return 0;
  }

  static pw.Widget _heading(String text, int level) {
    final size = switch (level) {
      1 => 18.0,
      2 => 16.0,
      3 => 13.5,
      _ => 12.0,
    };
    return pw.RichText(
      text: pw.TextSpan(
        text: text,
        style: pw.TextStyle(
          fontSize: size,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.blue800,
        ),
      ),
    );
  }

  static pw.Widget _paragraph(String text) => pw.RichText(
        text: pw.TextSpan(
          style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 1.3),
          children: _inlineSpans(text, const pw.TextStyle(fontSize: 10.5)),
        ),
      );

  static pw.Widget _listItem(String marker, String text, int indent) {
    return pw.Padding(
      padding: pw.EdgeInsets.only(left: indent * 14.0),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 16,
            child: pw.Text(
              marker,
              style: const pw.TextStyle(fontSize: 10.5),
            ),
          ),
          pw.Expanded(
            child: pw.RichText(
              text: pw.TextSpan(
                style:
                    const pw.TextStyle(fontSize: 10.5, lineSpacing: 1.3),
                children:
                    _inlineSpans(text, const pw.TextStyle(fontSize: 10.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _blockquote(String text) => pw.Container(
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            left: pw.BorderSide(color: PdfColors.grey400, width: 2),
          ),
        ),
        padding: const pw.EdgeInsets.only(left: 10),
        child: pw.RichText(
          text: pw.TextSpan(
            style: pw.TextStyle(
              fontSize: 10,
              fontStyle: pw.FontStyle.italic,
              color: PdfColors.grey700,
            ),
            children: _inlineSpans(
              text,
              pw.TextStyle(
                fontSize: 10,
                fontStyle: pw.FontStyle.italic,
                color: PdfColors.grey700,
              ),
            ),
          ),
        ),
      );

  /// Tokenize a single line into [pw.TextSpan]s for bold/code/link.
  static List<pw.TextSpan> _inlineSpans(String text, pw.TextStyle base) {
    final spans = <pw.TextSpan>[];
    var last = 0;
    for (final match in _inlineRe.allMatches(text)) {
      if (match.start > last) {
        spans.add(pw.TextSpan(text: text.substring(last, match.start), style: base));
      }
      if (match.group(1) != null) {
        spans.add(pw.TextSpan(
          text: match.group(1),
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: base.fontSize,
          ),
        ));
      } else if (match.group(2) != null) {
        // Link: render the label underlined + the URL in parentheses (no tap in
        // PDF, so include the destination so it stays useful).
        final label = match.group(2)!;
        final url = match.group(3)!;
        spans.add(pw.TextSpan(
          text: '$label ($url)',
          style: pw.TextStyle(
            color: PdfColors.blue700,
            decoration: pw.TextDecoration.underline,
            fontSize: base.fontSize,
          ),
        ));
      } else if (match.group(4) != null) {
        spans.add(pw.TextSpan(
          text: match.group(4),
          style: pw.TextStyle(
            color: PdfColors.purple800,
            fontSize: (base.fontSize ?? 10) * 0.92,
          ),
        ));
      }
      last = match.end;
    }
    if (last < text.length) {
      spans.add(pw.TextSpan(text: text.substring(last), style: base));
    }
    return spans;
  }

  // ── Value helpers ─────────────────────────────────────────────────────────

  static double _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static String _cellString(Object? v) {
    if (v == null) return '';
    if (v is num) return fmtMoney(v.toDouble());
    return v.toString();
  }

  static String _monthLabel(Object? year, Object? month) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final m = month is num ? month.toInt() : int.tryParse('$month') ?? 0;
    final y = year is num ? year.toInt() : int.tryParse('$year') ?? 0;
    final name = (m >= 1 && m <= 12) ? names[m - 1] : '';
    return y != 0 ? '$name $y' : name;
  }

  /// Parse a `#RRGGBB` (or `#RGB` / `RRGGBB`) hex string into a [PdfColor].
  /// Falls back to a calm blue when missing/unparseable.
  static PdfColor _pdfColor(Object? hex) {
    var h = (hex ?? '').toString().trim();
    if (h.isEmpty) return PdfColors.blue700;
    h = h.replaceFirst('#', '');
    if (h.length == 3) {
      h = h.split('').map((c) => '$c$c').join();
    }
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    if (v == null) return PdfColors.blue700;
    return PdfColor.fromInt(v);
  }
}

class _StatCell {
  const _StatCell(this.label, this.value);
  final String label;
  final double value;
}

/// One piece of the interleaved report document: either a markdown text
/// segment or an inline chart referenced by its 0-based index.
class _Segment {
  const _Segment.text(this.text)
      : isChart = false,
        chartIndex = null;
  const _Segment.chart(this.chartIndex)
      : isChart = true,
        text = null;

  final bool isChart;
  final int? chartIndex;
  final String? text;
}