import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_fonts/google_fonts.dart';

import '../../app/widgets/changelog_markdown.dart';

/// Opens a read-only "What's new" sheet showing the changelog for the
/// currently installed [version]. The entry is read from the `CHANGELOG.md`
/// bundled as a Flutter asset, so it works offline and never hits the GitHub
/// API — this is the post-install companion to the update sheet, letting users
/// revisit what changed in the version they're running.
Future<void> showWhatsNewSheet(BuildContext context, {required String version}) async {
  final source = await _extractEntryForVersion(version);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _WhatsNewSheet(version: version, source: source),
  );
}

/// Reads the bundled `CHANGELOG.md` and returns the entry block for [version]
/// (the lines from its `## vX.X.X` heading up to the next entry / `---`),
/// or an empty string if no matching entry is found.
Future<String> _extractEntryForVersion(String version) async {
  final raw = await rootBundle.loadString('CHANGELOG.md');
  final target = version.startsWith('v') ? version : 'v$version';
  final lines = raw.replaceAll('\r\n', '\n').split('\n');
  final headingRe = RegExp(r'^##\s+(v\d+\.\d+\.\d+)');

  int start = -1;
  for (var i = 0; i < lines.length; i++) {
    final m = headingRe.firstMatch(lines[i]);
    if (m != null && m.group(1) == target) {
      start = i;
      break;
    }
  }
  if (start < 0) return '';

  final out = <String>[];
  for (var i = start; i < lines.length; i++) {
    final line = lines[i];
    if (i > start && headingRe.hasMatch(line)) break; // next version entry
    if (RegExp(r'^---\s*$').hasMatch(line)) break; // entry separator
    out.add(line);
  }

  while (out.isNotEmpty && out.last.trim().isEmpty) {
    out.removeLast();
  }
  return out.join('\n');
}

class _WhatsNewSheet extends StatelessWidget {
  const _WhatsNewSheet({required this.version, required this.source});

  final String version;
  final String source;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
              child: Row(
                children: [
                  const Icon(Icons.new_releases_outlined, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "What's New",
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Installed: v$version',
                            style: tt.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: source.isNotEmpty
                    ? ChangelogMarkdown(source: source)
                    : Text(
                        'No release notes found for v$version.',
                        style: tt.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant),
                      ),
              ),
            ),
            // Footer
            Container(
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(color: cs.outlineVariant, width: 1)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}