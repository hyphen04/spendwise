import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../data/models/transaction_row.dart';
import '../../../state/dues_providers.dart';
import '../../../state/transactions_providers.dart';
import 'add_edit_transaction_sheet.dart';

Future<void> showTransactionDetailSheet(
  BuildContext context, {
  required TransactionRow row,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _DetailSheet(row: row),
  );
}

class _DetailSheet extends ConsumerStatefulWidget {
  const _DetailSheet({required this.row});
  final TransactionRow row;

  @override
  ConsumerState<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends ConsumerState<_DetailSheet> {
  @override
  Widget build(BuildContext context) {
    final tx = widget.row.transaction;
    final cs = Theme.of(context).colorScheme;
    final isTransfer = tx.kind.startsWith('transfer');
    final sign = isTransfer ? '' : (tx.kind == 'expense' ? '−' : '+');

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Drag handle ─────────────────────────────────────────────────
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Hero: emoji + amount + title ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  // Category/transfer emoji circle
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainer,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      isTransfer ? '⇄' : widget.row.categoryIcon,
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Amount
                  Text(
                    '$sign₹${_fmt(tx.amount)}',
                    style: GoogleFonts.manrope(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Kind badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tx.kind[0].toUpperCase() + tx.kind.substring(1),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Metadata card ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.calendar_today_outlined,
                      label: 'Date',
                      value: _formatDate(tx.transactionDate),
                    ),
                    _Divider(),
                    _InfoRow(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Account',
                      value: '${widget.row.accountIcon} ${widget.row.accountName}',
                    ),
                    if (!isTransfer) ...[
                      _Divider(),
                      _InfoRow(
                        icon: Icons.grid_view_rounded,
                        label: 'Category',
                        value: '${widget.row.categoryIcon} ${widget.row.categoryName}',
                      ),
                    ],
                    _Divider(),
                    _InfoRow(
                      icon: Icons.payment_outlined,
                      label: 'Mode',
                      value: '${widget.row.modeIcon} ${widget.row.modeName}',
                    ),
                    if (tx.note.isNotEmpty) ...[
                      _Divider(),
                      _InfoRow(
                        icon: Icons.notes_rounded,
                        label: 'Note',
                        value: tx.note,
                      ),
                    ],
                  ],
                ),
              ),
            ),


            const SizedBox(height: 24),

            // ── Actions ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: 'Edit',
                      icon: Icons.edit_outlined,
                      filled: false,
                      onTap: () {
                        Navigator.pop(context);
                        showAddEditTransactionSheet(context, editing: tx, toAccountId: widget.row.transferPairAccount?.id);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionButton(
                      label: 'Delete',
                      icon: Icons.delete_outline_rounded,
                      filled: true,
                      danger: true,
                      onTap: () => _delete(context),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final tx = widget.row.transaction;
    final settlement = await ref.read(duesRepositoryProvider).getSettlementForTransaction(tx.id);
    if (!mounted || !context.mounted) return;
    
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: Text(settlement != null
            ? 'This transaction is linked to a Dues settlement.\n\nDo you also want to undo the Dues settlement? (This will mark the tiffin/dues entries as unsettled again)'
            : (tx.kind.startsWith('transfer')
                ? 'Delete both legs of this transfer?'
                : 'Permanently delete this transaction?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'cancel'),
            child: const Text('Cancel'),
          ),
          if (settlement != null)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'delete_tx_only'),
              child: const Text('Delete Tx Only'),
            ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, settlement != null ? 'delete_and_undo' : 'delete'),
            child: Text(settlement != null ? 'Undo & Delete' : 'Delete'),
          ),
        ],
      ),
    );
    
    if (result != null && result != 'cancel' && mounted) {
      if (result == 'delete_and_undo' && settlement != null) {
        await ref.read(duesRepositoryProvider).undoSettlement(settlement.id);
      }
      await ref.read(transactionsRepositoryProvider).delete(tx.id);
      if (mounted && context.mounted) Navigator.pop(context);
    }
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w400,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.5,
      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
      indent: 42,
      endIndent: 0,
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = danger ? cs.error : cs.onSurface;
    final fg = danger ? cs.onError : cs.surface;

    if (filled) {
      return FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: cs.onSurface,
        side: BorderSide(color: cs.outline),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

String _fmt(double v) {
  if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(2)}Cr';
  if (v >= 100000) return '${(v / 100000).toStringAsFixed(2)}L';
  if (v == v.truncateToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2);
}

String _formatDate(String iso) {
  try {
    final dt = DateTime.parse(iso);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  } catch (_) {
    return iso;
  }
}
