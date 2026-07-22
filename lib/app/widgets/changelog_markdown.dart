import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../app/themes/app_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders the subset of Markdown used in SpendWise release notes:
/// `#`–`####` headings, `-` / `*` bullets (one level of nesting), numbered
/// lists (`1.`), `>` blockquotes, horizontal rules (`---`), and inline
/// `**bold**`, `~~strike~~`, `` `code` ``, `[text](url)` links, and
/// `![alt](url)` images (rendered as the alt text).
///
/// Intentionally dependency-free and forgiving: unsupported syntax degrades to
/// plain text instead of showing literal markers, so release notes stay
/// readable even if an author strays from the supported set. Tuned to the
/// CHANGELOG format (`## vX.X.X — date`, `### Added/Changed/Fixed`).
class ChangelogMarkdown extends StatelessWidget {
  const ChangelogMarkdown({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: _buildBlocks(source, theme.textTheme, theme.colorScheme, messenger),
    );
  }

  static final RegExp _hrRe = RegExp(r'^\s*(-{3,}|\*{3,}|_{3,})\s*$');
  static final RegExp _numberedRe = RegExp(r'^(\s*)(\d{1,3})\.\s+(.*)$');
  static final RegExp _bulletRe = RegExp(r'^(\s*)(?:[-*])\s+(.*)$');

  List<Widget> _buildBlocks(
      String src, TextTheme tt, ColorScheme cs, ScaffoldMessengerState? m) {
    final lines = src.replaceAll('\r\n', '\n').split('\n');
    final blocks = <Widget>[];
    final items = <_ListItem>[];
    final quote = <String>[];

    void flushItems() {
      if (items.isEmpty) return;
      blocks.add(_listBlock(items, tt, cs, m));
      blocks.add(const SizedBox(height: 14));
      items.clear();
    }

    void flushQuote() {
      if (quote.isEmpty) return;
      blocks.add(_blockquote(quote, tt, cs, m));
      blocks.add(const SizedBox(height: 14));
      quote.clear();
    }

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        flushItems();
        flushQuote();
        continue;
      }

      if (_hrRe.hasMatch(line)) {
        flushItems();
        flushQuote();
        blocks.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, thickness: 1, color: cs.outlineVariant),
        ));
        blocks.add(const SizedBox(height: 12));
        continue;
      }

      final level = _headingLevel(line);
      if (level > 0) {
        flushItems();
        flushQuote();
        blocks.add(_heading(line.substring(level + 1).trim(), level, tt, cs, m));
        blocks.add(const SizedBox(height: 12));
        continue;
      }

      if (line.startsWith('>')) {
        flushItems();
        quote.add(line.replaceFirst(RegExp(r'^>\s?'), ''));
        continue;
      }

      final numbered = _numberedRe.firstMatch(line);
      if (numbered != null) {
        flushQuote();
        final indent = (numbered.group(1)!.length ~/ 2).clamp(0, 1);
        items.add(_ListItem(
            indent: indent, text: numbered.group(3)!, marker: '${numbered.group(2)}.'));
        continue;
      }

      final bullet = _bulletRe.firstMatch(line);
      if (bullet != null) {
        flushQuote();
        final indent = (bullet.group(1)!.length ~/ 2).clamp(0, 1);
        items.add(_ListItem(indent: indent, text: bullet.group(2)!));
        continue;
      }

      flushItems();
      flushQuote();
      blocks.add(_paragraph(line, tt, cs, m));
      blocks.add(const SizedBox(height: 10));
    }

    flushItems();
    flushQuote();

    if (blocks.isNotEmpty && blocks.last is SizedBox) blocks.removeLast();
    return blocks;
  }

  int _headingLevel(String line) {
    var level = 0;
    while (level < line.length && line[level] == '#') {
      level++;
    }
    if (level >= 1 && level <= 4 && line.length > level && line[level] == ' ') {
      return level;
    }
    return 0;
  }

  Widget _heading(String text, int level, TextTheme tt, ColorScheme cs,
      ScaffoldMessengerState? m) {
    if (level <= 2) {
      // Version line, e.g. "vX.X.X — 2026-07-09".
      return Text.rich(
        _inline(
          text,
          tt.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface) ??
              const TextStyle(fontWeight: FontWeight.w800),
          cs,
          m,
        ),
      );
    }

    if (level == 3) {
      // Section labels: "Added" / "Changed" / "Fixed".
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 15,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: tt.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                    letterSpacing: 0.4,
                  ),
            ),
          ),
        ],
      );
    }

    // h4 — minor sub-heading.
    return Text.rich(
      _inline(
        text,
        tt.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface) ??
            const TextStyle(fontWeight: FontWeight.w700),
        cs,
        m,
      ),
    );
  }

  Widget _listBlock(List<_ListItem> items, TextTheme tt, ColorScheme cs,
      ScaffoldMessengerState? m) {
    final bodyStyle = tt.bodyMedium?.copyWith(height: 1.5, color: cs.onSurfaceVariant) ??
        const TextStyle(height: 1.5);
    final markerStyle = tt.bodyMedium?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ) ??
        const TextStyle();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Padding(
            padding: EdgeInsets.only(left: items[i].indent * 16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(
                  width: 20,
                  child: Text(
                    items[i].marker ??
                        (items[i].indent == 0 ? '•' : '◦'),
                    style: markerStyle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text.rich(_inline(items[i].text, bodyStyle, cs, m))),
              ],
            ),
          ),
          if (i < items.length - 1) const SizedBox(height: 7),
        ],
      ],
    );
  }

  Widget _blockquote(List<String> lines, TextTheme tt, ColorScheme cs,
      ScaffoldMessengerState? m) {
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: cs.outlineVariant, width: 2)),
      ),
      padding: const EdgeInsets.only(left: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            Text.rich(
              _inline(
                lines[i],
                tt.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                    ) ??
                    const TextStyle(fontStyle: FontStyle.italic),
                cs,
                m,
              ),
            ),
            if (i < lines.length - 1) const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Widget _paragraph(String text, TextTheme tt, ColorScheme cs,
      ScaffoldMessengerState? m) {
    return Text.rich(
      _inline(
        text,
        tt.bodyMedium?.copyWith(height: 1.5, color: cs.onSurfaceVariant) ??
            const TextStyle(height: 1.5),
        cs,
        m,
      ),
    );
  }

  // Order matters: `**bold**` before `*`, image `![..](..)` before link
  // `[..](..)`, and `~~strike~~` / `` `code` `` as their own groups.
  static final RegExp _inlineRe = RegExp(
    r'\*\*(.+?)\*\*' // 1: bold
    r'|~~(.+?)~~' // 2: strikethrough
    r'|!\[([^\]]*)\]\(([^)]+)\)' // 3: image alt, 4: image url
    r'|\[([^\]]+)\]\(([^)]+)\)' // 5: link text, 6: link url
    r'|`([^`]+)`', // 7: code
  );

  /// Tokenizes a single line into [TextSpan]s for inline formatting.
  TextSpan _inline(String text, TextStyle base, ColorScheme cs,
      ScaffoldMessengerState? m) {
    final spans = <InlineSpan>[];
    var last = 0;

    for (final match in _inlineRe.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start), style: base));
      }

      if (match.group(1) != null) {
        spans.add(TextSpan(
          text: match.group(1),
          style: base.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface),
        ));
      } else if (match.group(2) != null) {
        spans.add(TextSpan(
          text: match.group(2),
          style: base.copyWith(decoration: TextDecoration.lineThrough),
        ));
      } else if (match.group(3) != null) {
        // Image: we can't render remote images inline — show the alt text.
        final alt = match.group(3)!.trim();
        spans.add(TextSpan(
          text: alt.isEmpty ? '🖼' : alt,
          style: base.copyWith(fontStyle: FontStyle.italic, color: cs.onSurfaceVariant),
        ));
      } else if (match.group(5) != null) {
        final label = match.group(5)!;
        final url = match.group(6)!;
        spans.add(TextSpan(
          text: label,
          style: base.copyWith(color: cs.primary, decoration: TextDecoration.underline),
          recognizer: TapGestureRecognizer()
            ..onTap = () => _launchUrl(url, m),
        ));
      } else if (match.group(7) != null) {
        spans.add(TextSpan(
          text: match.group(7),
          style: spaceGrotesk(
            fontSize: (base.fontSize ?? 14) * 0.9,
            color: cs.primary,
            backgroundColor: cs.surfaceContainer,
          ),
        ));
      }

      last = match.end;
    }

    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: base));
    }

    return TextSpan(style: base, children: spans);
  }

  Future<void> _launchUrl(String url, ScaffoldMessengerState? m) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && m != null) {
      m.showSnackBar(SnackBar(content: Text('Could not open link: $url')));
    }
  }
}

/// A list item: a bullet (marker == null) or numbered entry (marker == "1.").
class _ListItem {
  const _ListItem({required this.indent, required this.text, this.marker});

  final int indent; // 0 = top-level, 1 = sub
  final String text;
  final String? marker;
}