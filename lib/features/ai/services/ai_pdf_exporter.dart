import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Renders an AI-generated narrative report (a Markdown string constrained to
/// the `ChangelogMarkdown` subset) into a shareable PDF.
///
/// Reuses the `pdf` package + `getTemporaryDirectory` + file-write pattern from
/// `PdfExporter`, but is kept separate so `PdfExporter` stays focused on
/// tabular exports. The Markdown→`pw` mapping mirrors
/// `ChangelogMarkdown`'s supported subset: `#`–`####` headings, `-`/`*` bullets
/// (one nesting level), numbered lists, `>` blockquotes, `---` rules, and
/// inline `**bold**` / `` `code` `` / `[text](url)`. Anything else degrades to
/// plain text so the PDF never shows literal markers.
class AiPdfExporter {
  AiPdfExporter._();

  /// Build the PDF for [markdown] covering [periodLabel] and return its path.
  static Future<String> export({
    required String markdown,
    required String periodLabel,
    String title = 'SpendWise — AI Report',
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) => [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Period: $periodLabel',
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 16),
          ..._renderMarkdown(markdown),
          pw.SizedBox(height: 24),
          pw.Text(
            'Generated on '
            '${DateTime.now().toIso8601String().substring(0, 16).replaceAll('T', ' ')} '
            '· SpendWise AI Copilot',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    final dir = await getTemporaryDirectory();
    final stamp =
        DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '');
    final file = File('${dir.path}/spendwise_ai_report_$stamp.pdf');
    await file.writeAsBytes(bytes);
    return file.path;
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
    // Inline chart markers (`{{chart:N}}`) from the on-screen report don't
    // render to PDF — charts can't be embedded here — so strip them first.
    // They sit on their own lines, which become blank lines (a small gap) here.
    final cleaned = src.replaceAll(RegExp(r'\{\{chart:\d+\}\}'), '');
    final lines = cleaned.replaceAll('\r\n', '\n').split('\n');
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
        blocks.add(_listItem(indent == 0 ? '•' : '◦', bullet.group(2)!, indent));
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
}