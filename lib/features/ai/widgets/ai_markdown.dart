import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../app/themes/app_fonts.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

/// Renders the Markdown the AI emits in chat replies and the report narrative.
///
/// Replaces the hand-rolled [ChangelogMarkdown] on AI surfaces with the
/// `flutter_markdown` engine, which supports fenced code blocks, tables, and
/// arbitrary nesting — so the prompts can now allow richer output. Stays
/// dependency-light on the changelog side: the What's New / changelog viewer
/// keeps [ChangelogMarkdown] (whose forgiving subset matches the parser rules
/// in CLAUDE.md); this widget is only for LLM-authored text.
///
/// Styling follows the app: PlusJakartaSans body, `colorScheme`-driven text,
/// monospace code via Space Grotesk, fenced code blocks with a Copy button,
/// tappable links opened externally via url_launcher (reusing the launch
/// handler pattern from `changelog_markdown.dart`), table borders, and
/// selectable text. Safe for streaming partial markdown — `flutter_markdown`
/// degrades gracefully on an unclosed fence (treats the rest as code) and
/// never throws on incomplete input.
class AiMarkdown extends StatelessWidget {
  const AiMarkdown({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final messenger = ScaffoldMessenger.maybeOf(context);

    return MarkdownBody(
      data: source,
      selectable: true,
      // GitHub-flavored extension set enables fenced code blocks + tables.
      extensionSet: md.ExtensionSet.gitHubFlavored,
      styleSheet: _styleSheet(theme, cs),
      builders: {
        'pre': _CodeBlockBuilder(cs: cs, messenger: messenger),
      },
      onTapLink: (text, href, title) => _launchUrl(href, messenger),
    );
  }

  /// App-styled sheet: PlusJakartaSans body, colorScheme-driven headings, a
  /// quiet surface for code blocks, and bordered tables.
  static MarkdownStyleSheet _styleSheet(ThemeData theme, ColorScheme cs) {
    final base = plusJakartaSans(
      fontSize: 14,
      height: 1.5,
      color: cs.onSurface,
    );
    return MarkdownStyleSheet(
      p: base,
      h1: base.copyWith(
          fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface),
      h2: base.copyWith(
          fontSize: 19, fontWeight: FontWeight.w800, color: cs.onSurface),
      h3: base.copyWith(
          fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface),
      h4: base.copyWith(
          fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface),
      h5: base.copyWith(
          fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface),
      h6: base.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant),
      strong: base.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface),
      em: base.copyWith(fontStyle: FontStyle.italic),
      del: base.copyWith(decoration: TextDecoration.lineThrough),
      blockquote: base.copyWith(
          color: cs.onSurfaceVariant, fontStyle: FontStyle.italic),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: cs.outlineVariant, width: 2)),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12),
      code: spaceGrotesk(
        fontSize: 12.5,
        color: cs.primary,
        backgroundColor: cs.surfaceContainer,
      ),
      listBullet: base.copyWith(color: cs.onSurfaceVariant),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: cs.outlineVariant, width: 1)),
      ),
      tableHead: base.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface),
      tableBody: base,
      tableBorder: TableBorder.all(
          color: cs.outlineVariant, width: 0.8, borderRadius: BorderRadius.circular(6)),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      tableColumnWidth: const FlexColumnWidth(),
    );
  }

  Future<void> _launchUrl(String? url, ScaffoldMessengerState? m) async {
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && m != null) {
      m.showSnackBar(SnackBar(content: Text('Could not open link: $url')));
    }
  }
}

/// Builds the fenced-code-block widget: a monospace, selectable code surface
/// with a Copy button. Registered for the `pre` element so inline `code`
/// (handled by [MarkdownStyleSheet.code]) is untouched.
class _CodeBlockBuilder extends MarkdownElementBuilder {
  _CodeBlockBuilder({required this.cs, required this.messenger});
  final ColorScheme cs;
  final ScaffoldMessengerState? messenger;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.textContent;
    return _CodeBlock(code: code, cs: cs, messenger: messenger);
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({
    required this.code,
    required this.cs,
    required this.messenger,
  });

  final String code;
  final ColorScheme cs;
  final ScaffoldMessengerState? messenger;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 36, 12),
            child: Text(
              code,
              style: spaceGrotesk(
                fontSize: 12.5,
                height: 1.45,
                color: cs.onSurface,
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              tooltip: 'Copy',
              icon: Icon(Icons.copy_rounded, size: 16, color: cs.onSurfaceVariant),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                messenger?.showSnackBar(
                  const SnackBar(
                    content: Text('Copied'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}