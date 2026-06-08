import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/themes/app_colors.dart';
import '../../../data/models/transaction_row.dart';

/// Flat monochrome transaction row — no card, no shadow, no colored amounts.
/// Income vs expense is shown by the +/− sign only.
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.row,
    required this.onTap,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    this.highlight = '',
  });

  final TransactionRow row;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  /// When non-empty, the matching substring in the title and note is bolded.
  final String highlight;

  @override
  Widget build(BuildContext context) {
    final tx = row.transaction;
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final isTransfer = tx.kind == 'transfer';
    final sign = isTransfer ? '' : (tx.kind == 'expense' ? '−' : '+');
    final amountColor = appColors.forKind(tx.kind);
    final avatarBg = appColors.containerForKind(tx.kind);

    return InkWell(
      onTap: onTap,
      onLongPress: () => _showActionsSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            // Emoji avatar — kind-tinted circle
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: avatarBg,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                isTransfer ? '⇄' : row.categoryIcon,
                style: const TextStyle(fontSize: 22),
              ),
            ),
            const SizedBox(width: 14),
            // Title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HighlightText(
                    text: isTransfer ? 'Transfer' : row.categoryName,
                    highlight: highlight,
                    baseStyle: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                    matchStyle: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  _HighlightText(
                    text: tx.note.isNotEmpty ? tx.note : row.accountName,
                    highlight: highlight,
                    baseStyle: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: cs.onSurfaceVariant,
                    ),
                    matchStyle: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Amount — colored by kind
            Text(
              '$sign₹${_fmtAmt(tx.amount)}',
              style: GoogleFonts.manrope(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: amountColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showActionsSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(ctx);
                onEdit();
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Duplicate'),
              onTap: () {
                Navigator.pop(ctx);
                onDuplicate();
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: cs.onSurface),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(ctx);
                onDelete();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Highlight helper ───────────────────────────────────────────────────────────

class _HighlightText extends StatelessWidget {
  const _HighlightText({
    required this.text,
    required this.highlight,
    required this.baseStyle,
    required this.matchStyle,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final String highlight;
  final TextStyle baseStyle;
  final TextStyle matchStyle;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    if (highlight.isEmpty) {
      return Text(text, style: baseStyle, maxLines: maxLines, overflow: overflow);
    }
    final lower = text.toLowerCase();
    final lowerQ = highlight.toLowerCase();
    final idx = lower.indexOf(lowerQ);
    if (idx < 0) {
      return Text(text, style: baseStyle, maxLines: maxLines, overflow: overflow);
    }
    return Text.rich(
      TextSpan(children: [
        if (idx > 0) TextSpan(text: text.substring(0, idx), style: baseStyle),
        TextSpan(
            text: text.substring(idx, idx + highlight.length),
            style: matchStyle),
        if (idx + highlight.length < text.length)
          TextSpan(
              text: text.substring(idx + highlight.length), style: baseStyle),
      ]),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

String _fmtAmt(double v) {
  if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
  if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
  if (v == v.truncateToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2);
}
