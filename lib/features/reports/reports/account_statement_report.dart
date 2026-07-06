import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../data/db/app_database.dart';

import '../../../state/manage_providers.dart';
import '../../../state/reports_providers.dart';
import '../widgets/report_period_app_bar.dart';


class AccountStatementReport extends ConsumerStatefulWidget {
  const AccountStatementReport({
    super.key,
    required this.year,
    required this.month,
  });
  final int year;
  final int month;

  @override
  ConsumerState<AccountStatementReport> createState() =>
      _AccountStatementReportState();
}

class _AccountStatementReportState
    extends ConsumerState<AccountStatementReport> {
  String? _accountId;
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    _year = widget.year;
    _month = widget.month;
  }

  void _prevMonth() {
    setState(() {
      if (_month == 1) {
        _month = 12;
        _year--;
      } else {
        _month--;
      }
    });
  }

  void _nextMonth() {
    setState(() {
      if (_month == 12) {
        _month = 1;
        _year++;
      } else {
        _month++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accsAsync = ref.watch(accountsStreamProvider);
    final from = DateTime(_year, _month).toIso8601String();
    final to = DateTime(_year, _month + 1).toIso8601String();
    final monthLabel = '${_months[_month - 1]} $_year';

    final accounts = (accsAsync.valueOrNull ?? <Account>[])
        .where((a) => !a.isArchived)
        .toList();

    if (_accountId == null && accounts.isNotEmpty) {
      _accountId = accounts.first.id;
    }

    return Scaffold(
      appBar: ReportPeriodAppBar(
        title: 'Account Statement',
        subtitle: monthLabel,
        onPrevious: _prevMonth,
        onNext: _nextMonth,
      ),
      body: Column(
        children: [
          // Account picker
          if (accounts.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: DropdownButtonFormField<String>(
                initialValue: _accountId,
                decoration:
                    const InputDecoration(labelText: 'Account', isDense: true),
                items: accounts
                    .map((a) => DropdownMenuItem(
                          value: a.id,
                          child: Text('${a.icon} ${a.name}'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _accountId = v),
              ),
            ),
          const SizedBox(height: 12),
          if (_accountId == null)
            Expanded(
              child: Center(
                child: Text('No accounts',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            )
          else
            Expanded(
              child: _StatementList(
                accountId: _accountId!,
                from: from,
                to: to,
              ),
            ),
        ],
      ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

class _StatementList extends ConsumerWidget {
  const _StatementList({
    required this.accountId,
    required this.from,
    required this.to,
  });
  final String accountId;
  final String from;
  final String to;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final async = ref.watch(accountStatementProvider((accountId, from, to)));
    final balanceAsync = ref.watch(accountBalanceProvider(accountId));
    final periodBalancesAsync = ref.watch(accountStatementBalancesProvider((accountId, from, to)));
    
    final catMap = {
      for (final c in ref.watch(categoriesStreamProvider).valueOrNull ?? [])
        c.id: c.name
    };

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (txs) {
        double monthIncome = 0.0;
        double monthExpense = 0.0;
        for (final t in txs) {
          if (t.kind == 'income' || t.kind == 'transfer_in') {
            monthIncome += t.amount;
          } else if (t.kind == 'expense' || t.kind == 'transfer_out') {
            monthExpense += t.amount;
          }
        }
        final netFlow = monthIncome - monthExpense;

        return ListView.builder(
          itemCount: txs.isEmpty ? 2 : txs.length + 2,
          itemBuilder: (ctx, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: periodBalancesAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (b) => _StatementSummaryCard(
                    opening: b.$1,
                    closing: b.$2,
                    income: monthIncome,
                    expense: monthExpense,
                    currentBalanceAsync: balanceAsync,
                  ),
                ),
              );
            }
            if (i == 1) {
              if (txs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Center(
                    child: Text('No transactions in this month',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: cs.onSurfaceVariant,
                            )),
                  ),
                );
              }
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${txs.length} transactions',
                            style: TextStyle(color: cs.onSurfaceVariant)),
                        Text(
                          'Month Flow: ${netFlow >= 0 ? '+' : ''}₹${_fmt(netFlow)}',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: netFlow >= 0
                                  ? cs.onSurface
                                  : cs.error),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                ],
              );
            }
            
            final tx = txs[i - 2];
            final isIncome = tx.kind == 'income' || tx.kind == 'transfer_in';
            final isTransfer = tx.kind.startsWith('transfer');
            return Column(
              children: [
                ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: isTransfer
                        ? cs.onSurface.withAlpha(20)
                        : (isIncome
                            ? cs.onSurface.withAlpha(20)
                            : cs.errorContainer),
                    child: Text(
                      isTransfer ? '⇄' : (isIncome ? '↑' : '↓'),
                      style: TextStyle(
                        color: isTransfer
                            ? cs.onSurface
                            : (isIncome
                                ? cs.onSurface
                                : cs.onErrorContainer),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  title: Text(
                      catMap[tx.categoryId] ?? (isTransfer ? 'Transfer' : tx.kind),
                      style: const TextStyle(fontSize: 14)),
                  subtitle: tx.note.isNotEmpty
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(tx.note,
                                style: const TextStyle(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            Text(tx.transactionDate.substring(0, 10),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant)),
                          ],
                        )
                      : Text(tx.transactionDate.substring(0, 10),
                          style: const TextStyle(fontSize: 12)),
                  trailing: Text(
                    '${isIncome ? '+' : '-'}₹${_fmt(tx.amount)}',
                    style: TextStyle(
                        color: isIncome
                            ? cs.onSurface
                            : cs.error,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                  ),
                ),
                if (i - 2 < txs.length - 1)
                  const Divider(height: 1, indent: 56),
              ],
            );
          },
        );
        },
      );
  }

}

class _StatementSummaryCard extends StatelessWidget {
  const _StatementSummaryCard({
    required this.opening,
    required this.closing,
    required this.income,
    required this.expense,
    required this.currentBalanceAsync,
  });
  final double opening;
  final double closing;
  final double income;
  final double expense;
  final AsyncValue<double> currentBalanceAsync;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          _FlowRow(label: 'Opening Balance', amount: opening, color: cs.onSurfaceVariant),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          _FlowRow(label: 'In (+)', amount: income, color: const Color(0xFF16A34A), prefix: '+ '),
          const SizedBox(height: 12),
          _FlowRow(label: 'Out (-)', amount: expense, color: const Color(0xFFDC2626), prefix: '- '),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          _FlowRow(label: 'Closing Balance', amount: closing, color: cs.onSurface, isBold: true),
          
          // Current Balance (As of Today)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.account_balance_wallet_outlined, size: 18, color: cs.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Text('Current Balance: ', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w500, color: cs.onPrimaryContainer)),
                  currentBalanceAsync.when(
                    loading: () => const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    error: (e, _) => Text('Error', style: TextStyle(color: cs.error, fontSize: 13)),
                    data: (balance) => Text(
                      '₹${_fmt(balance)}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: balance >= 0 ? cs.onPrimaryContainer : cs.error,
                      ),
                    ),
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

class _FlowRow extends StatelessWidget {
  const _FlowRow({
    required this.label, 
    required this.amount, 
    required this.color,
    this.prefix = '',
    this.isBold = false,
  });
  final String label;
  final double amount;
  final Color color;
  final String prefix;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: color,
            fontSize: isBold ? 15 : 14,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        Text(
          '$prefix₹${_fmt(amount.abs())}',
          style: GoogleFonts.plusJakartaSans(
            color: color,
            fontSize: isBold ? 16 : 15,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

String _fmt(double v) =>
    v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
