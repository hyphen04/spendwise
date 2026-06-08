import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/models/transaction_row.dart';
import '../../state/search_provider.dart';
import '../../state/transactions_providers.dart';
import '../manage/sheets/account_form_sheet.dart';
import '../manage/sheets/category_form_sheet.dart';
import '../manage/sheets/mode_form_sheet.dart';
import '../transactions/sheets/add_edit_transaction_sheet.dart';
import '../transactions/sheets/transaction_detail_sheet.dart';
import '../transactions/widgets/transaction_tile.dart';

void showSearchSheet(BuildContext context) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return FadeTransition(
          opacity: animation,
          child: const _SearchSheet(),
        );
      },
    ),
  );
}

class _SearchSheet extends ConsumerStatefulWidget {
  const _SearchSheet();

  @override
  ConsumerState<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends ConsumerState<_SearchSheet> {
  final _ctrl = TextEditingController();
  // The query that actually drives the provider — updated after debounce.
  String _debouncedQuery = '';
  // The raw value shown in the field — used for highlight rendering.
  String _rawQuery = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    final trimmed = v.trim();
    setState(() => _rawQuery = trimmed);
    _debounce?.cancel();
    if (trimmed.isEmpty) {
      setState(() => _debouncedQuery = '');
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _debouncedQuery = trimmed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final results = ref.watch(globalSearchProvider(_debouncedQuery));
    final recent = ref.watch(recentTransactionsProvider);
    final isEmpty = _debouncedQuery.isEmpty && _rawQuery.isEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ── Glassmorphism Background ──────────────────────────────────────
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  color: cs.surface.withValues(alpha: 0.65),
                ),
              ),
            ),
          ),

          // ── Content ───────────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // ── Search field ──────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(50),
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _ctrl,
                      autofocus: true,
                      onChanged: _onChanged,
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search SpendWise...',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 8, right: 4),
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back_rounded),
                            color: cs.onSurface,
                            iconSize: 24,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                        suffixIcon: _rawQuery.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: IconButton(
                                  icon: const Icon(Icons.cancel_rounded, size: 22),
                                  color: cs.onSurfaceVariant,
                                  onPressed: () {
                                    _ctrl.clear();
                                    _debounce?.cancel();
                                    setState(() {
                                      _rawQuery = '';
                                      _debouncedQuery = '';
                                    });
                                  },
                                ),
                              )
                            : null,
                        border: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),

                // ── Results area ──────────────────────────────────────────────
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
                    physics: const BouncingScrollPhysics(),
            children: [
              if (isEmpty) ...[
                // Recent transactions
                if (recent.isNotEmpty) ...[
                  _SectionHeader(label: 'RECENT', cs: cs),
                  ..._buildTxTiles(recent, cs, highlight: ''),
                ] else
                  _EmptyHint(
                    cs: cs,
                    message: 'Type to search across all transactions,\ncategories, accounts, and more.',
                  ),
              ] else if (_debouncedQuery.isEmpty)
                // Still typing but debounce hasn't fired — show nothing
                const SizedBox.shrink()
              else if (results.isEmpty)
                _EmptyHint(
                  cs: cs,
                  message: 'No results for "$_debouncedQuery".',
                )
              else ...[
                // ── Transactions ────────────────────────────────────────
                if (results.transactions.isNotEmpty) ...[
                  _SectionHeader(
                    label: 'TRANSACTIONS',
                    count: results.transactions.length,
                    cs: cs,
                  ),
                  ..._buildTxTiles(results.transactions, cs,
                      highlight: _debouncedQuery),
                ],

                // ── Categories ──────────────────────────────────────────
                if (results.categories.isNotEmpty) ...[
                  _SectionHeader(
                    label: 'CATEGORIES',
                    count: results.categories.length,
                    cs: cs,
                  ),
                  ...results.categories.map(
                    (cat) => _EntityTile(
                      icon: cat.icon,
                      label: cat.name,
                      sublabel: cat.kind == 'both'
                          ? 'income & expense'
                          : cat.kind,
                      highlight: _debouncedQuery,
                      cs: cs,
                      onTap: () => showCategoryFormSheet(context, editing: cat),
                    ),
                  ),
                ],

                // ── Accounts ────────────────────────────────────────────
                if (results.accounts.isNotEmpty) ...[
                  _SectionHeader(
                    label: 'ACCOUNTS',
                    count: results.accounts.length,
                    cs: cs,
                  ),
                  ...results.accounts.map(
                    (acc) => _EntityTile(
                      icon: acc.icon,
                      label: acc.name,
                      sublabel: acc.currency,
                      highlight: _debouncedQuery,
                      cs: cs,
                      onTap: () => showAccountFormSheet(context, editing: acc),
                    ),
                  ),
                ],

                // ── Modes ───────────────────────────────────────────────
                if (results.modes.isNotEmpty) ...[
                  _SectionHeader(
                    label: 'PAYMENT MODES',
                    count: results.modes.length,
                    cs: cs,
                  ),
                  ...results.modes.map(
                    (mode) => _EntityTile(
                      icon: mode.icon,
                      label: mode.name,
                      highlight: _debouncedQuery,
                      cs: cs,
                      onTap: () => showModeFormSheet(context, editing: mode),
                    ),
                  ),
                ],

              ],
            ],
          ),
        ),
      ],
    ),
  ),
        ],
      ),
    );
  }

  List<Widget> _buildTxTiles(
    List<TransactionRow> rows,
    ColorScheme cs, {
    required String highlight,
  }) {
    final widgets = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      widgets.add(TransactionTile(
        row: row,
        highlight: highlight,
        onTap: () => showTransactionDetailSheet(context, row: row),
        onEdit: () =>
            showAddEditTransactionSheet(context, editing: row.transaction),
        onDuplicate: () => ref
            .read(transactionsRepositoryProvider)
            .duplicate(row.transaction),
        onDelete: () => ref
            .read(transactionsRepositoryProvider)
            .delete(row.transaction.id),
      ));
      if (i < rows.length - 1) {
        widgets.add(Divider(
          height: 1,
          thickness: 0.5,
          color: cs.outline,
          indent: 20,
          endIndent: 20,
        ));
      }
    }
    return widgets;
  }
}

// ── Section header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.cs, this.count});
  final String label;
  final ColorScheme cs;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Entity tile (category / account / mode) ────────────────────────────────────

class _EntityTile extends StatelessWidget {
  const _EntityTile({
    required this.icon,
    required this.label,
    required this.highlight,
    required this.cs,
    required this.onTap,
    this.sublabel,
  });

  final String icon;
  final String label;
  final String? sublabel;
  final String highlight;
  final ColorScheme cs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HighlightText(
                    text: label,
                    highlight: highlight,
                    baseStyle: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface,
                    ),
                    highlightStyle: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  if (sublabel != null)
                    Text(
                      sublabel!,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}


// ── Highlight text ─────────────────────────────────────────────────────────────

class _HighlightText extends StatelessWidget {
  const _HighlightText({
    required this.text,
    required this.highlight,
    required this.baseStyle,
    required this.highlightStyle,
  });

  final String text;
  final String highlight;
  final TextStyle baseStyle;
  final TextStyle highlightStyle;

  @override
  Widget build(BuildContext context) {
    if (highlight.isEmpty) return Text(text, style: baseStyle);
    final lower = text.toLowerCase();
    final lowerQ = highlight.toLowerCase();
    final idx = lower.indexOf(lowerQ);
    if (idx < 0) return Text(text, style: baseStyle);

    return Text.rich(TextSpan(children: [
      if (idx > 0) TextSpan(text: text.substring(0, idx), style: baseStyle),
      TextSpan(
          text: text.substring(idx, idx + highlight.length),
          style: highlightStyle),
      if (idx + highlight.length < text.length)
        TextSpan(
            text: text.substring(idx + highlight.length), style: baseStyle),
    ]));
  }
}

// ── Empty hint ─────────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.cs, required this.message});
  final ColorScheme cs;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 40),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 14, color: cs.onSurfaceVariant),
      ),
    );
  }
}
