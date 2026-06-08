import 'package:flutter/material.dart';
import 'import_models.dart';

class ImportPreviewSheet extends StatelessWidget {
  const ImportPreviewSheet({super.key, required this.preview});

  final ImportPreview preview;

  static Future<bool?> show(BuildContext context, ImportPreview preview) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ImportPreviewSheet(preview: preview),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final topPad = MediaQuery.paddingOf(context).top;
    final botPad = MediaQuery.paddingOf(context).bottom;

    final hasNew = preview.newEntityCount > 0;
    final hasErrors = preview.errorCount > 0;
    final canImport = preview.validCount > 0;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) => Column(
        children: [
          // Title
          Padding(
            padding: EdgeInsets.fromLTRB(20, topPad > 0 ? 4 : 4, 20, 8),
            child: Text(
              'Import Preview',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const Divider(height: 1),

          // Scrollable body
          Expanded(
            child: ListView(
              controller: controller,
              padding: EdgeInsets.fromLTRB(16, 16, 16, botPad + 16),
              children: [
                // ── Summary pills ────────────────────────────────────────
                Row(
                  children: [
                    _Pill(
                      label: '${preview.validCount}',
                      sublabel: 'to import',
                      color: cs.primaryContainer,
                      textColor: cs.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    _Pill(
                      label: '${preview.errorCount}',
                      sublabel: 'skipped',
                      color: hasErrors
                          ? cs.errorContainer
                          : cs.surfaceContainer,
                      textColor: hasErrors
                          ? cs.onErrorContainer
                          : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    _Pill(
                      label: '${preview.newEntityCount}',
                      sublabel: 'new entities',
                      color: hasNew
                          ? cs.tertiaryContainer
                          : cs.surfaceContainer,
                      textColor: hasNew
                          ? cs.onTertiaryContainer
                          : cs.onSurfaceVariant,
                    ),
                  ],
                ),

                // ── New entities ─────────────────────────────────────────
                if (hasNew) ...[
                  const SizedBox(height: 20),
                  _sectionLabel('New entities will be created', cs, tt),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: cs.tertiaryContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (preview.newAccountNames.isNotEmpty)
                          _EntityGroup(
                            icon: '🏦',
                            label: 'Accounts',
                            names: preview.newAccountNames.toList(),
                            cs: cs,
                            tt: tt,
                          ),
                        if (preview.newCategoryNames.isNotEmpty)
                          _EntityGroup(
                            icon: '🏷️',
                            label: 'Categories',
                            names: preview.newCategoryNames.toList(),
                            cs: cs,
                            tt: tt,
                          ),
                        if (preview.newModeNames.isNotEmpty)
                          _EntityGroup(
                            icon: '💳',
                            label: 'Modes',
                            names: preview.newModeNames.toList(),
                            cs: cs,
                            tt: tt,
                          ),
                      ],
                    ),
                  ),
                ],

                // ── Errors ───────────────────────────────────────────────
                if (hasErrors) ...[
                  const SizedBox(height: 20),
                  _sectionLabel(
                    '${preview.errorCount} row${preview.errorCount == 1 ? '' : 's'} skipped',
                    cs,
                    tt,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: cs.errorContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Column(
                      children: [
                        for (final err in preview.errors.take(10))
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Row ${err.rowIndex}',
                                  style: tt.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: cs.onErrorContainer,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    err.message,
                                    style: tt.bodySmall?.copyWith(
                                      color: cs.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (preview.errorCount > 10)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '… and ${preview.errorCount - 10} more',
                              style: tt.bodySmall?.copyWith(
                                color: cs.onErrorContainer,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],

                if (!canImport) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'No valid rows found. Fix the errors above and try again.',
                      style: tt.bodyMedium
                          ?.copyWith(color: cs.onErrorContainer),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // ── Actions ──────────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: canImport
                            ? () => Navigator.of(context).pop(true)
                            : null,
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: Text(
                          canImport
                              ? 'Import ${preview.validCount} transaction${preview.validCount == 1 ? '' : 's'}'
                              : 'Nothing to import',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String title, ColorScheme cs, TextTheme tt) => Text(
        title.toUpperCase(),
        style: tt.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.sublabel,
    required this.color,
    required this.textColor,
  });

  final String label;
  final String sublabel;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: tt.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: tt.labelSmall?.copyWith(color: textColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EntityGroup extends StatelessWidget {
  const _EntityGroup({
    required this.icon,
    required this.label,
    required this.names,
    required this.cs,
    required this.tt,
  });

  final String icon;
  final String label;
  final List<String> names;
  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: tt.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onTertiaryContainer,
                    ),
                  ),
                  TextSpan(
                    text: names.join(', '),
                    style: tt.labelSmall
                        ?.copyWith(color: cs.onTertiaryContainer),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
