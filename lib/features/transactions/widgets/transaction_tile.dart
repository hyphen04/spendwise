import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../../app/themes/app_fonts.dart';
import '../../../app/themes/app_colors.dart';
import '../../../app/utils/money_format.dart';
import '../../../data/models/transaction_row.dart';

/// Flat monochrome transaction row — no card, no shadow, no colored amounts.
/// Income vs expense is shown by the +/− sign only.
///
/// Swipe right→left reveals **Delete** (end pane); swipe left→right reveals
/// **Edit** + **Duplicate** (start pane). A plain tap opens the edit form
/// (see CLAUDE.md → List Row Interaction Rules).
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.row,
    required this.onTap,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.highlight = '',
  });

  final TransactionRow row;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  /// When non-empty, the matching substring in the title and note is bolded.
  final String highlight;

  @override
  Widget build(BuildContext context) {
    final tx = row.transaction;
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final isTransfer = tx.kind.startsWith('transfer');
    final sign = isTransfer ? '' : (tx.kind == 'expense' ? '−' : '+');
    final amountColor = appColors.forKind(tx.kind);
    final avatarBg = appColors.containerForKind(tx.kind);

    return Slidable(
      key: ValueKey(row.transaction.id),
      startActionPane: (onEdit != null || onDuplicate != null)
          ? ActionPane(
              motion: const DrawerMotion(),
              extentRatio: 0.5,
              children: [
                if (onEdit != null)
                  SlidableAction(
                    onPressed: (_) => onEdit!(),
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    icon: Icons.edit_outlined,
                    label: 'Edit',
                  ),
                if (onDuplicate != null)
                  SlidableAction(
                    onPressed: (_) => onDuplicate!(),
                    backgroundColor: cs.surfaceContainerHighest,
                    foregroundColor: cs.onSurface,
                    icon: Icons.content_copy_rounded,
                    label: 'Duplicate',
                  ),
              ],
            )
          : null,
      endActionPane: onDelete != null
          ? ActionPane(
              motion: const DrawerMotion(),
              extentRatio: 0.25,
              children: [
                SlidableAction(
                  onPressed: (_) => onDelete!(),
                  backgroundColor: appColors.expense,
                  foregroundColor: appColors.onExpense,
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                ),
              ],
            )
          : null,
      child: InkWell(
        onTap: onTap,
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
                    text: isTransfer ? '${row.accountName} ⇄ ${row.transferPairAccountName}' : row.categoryName,
                    highlight: highlight,
                    baseStyle: plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                    matchStyle: plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  _HighlightText(
                    text: tx.note.isNotEmpty ? tx.note : (isTransfer ? 'Transfer' : row.accountName),
                    highlight: highlight,
                    baseStyle: plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: cs.onSurfaceVariant,
                    ),
                    matchStyle: plusJakartaSans(
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
              style: plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: amountColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
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

// Full Indian-grouped amount (no K/L/Cr abbreviation) so each transaction's
// value is clearly readable. See `fmtGrouped` in money_format.dart.
String _fmtAmt(double v) => fmtGrouped(v);
