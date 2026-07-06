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
    
    final catMap = {
      for (final c in ref.watch(categoriesStreamProvider).valueOrNull ?? [])
        c.id: c.name
    };

    return Column(
      children: [
        // Top Balance Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: Row(
            children: [
              Text('Current Balance', style: GoogleFonts.inter(color: cs.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500)),
              const Spacer(),
              balanceAsync.when(
                loading: () => const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                error: (e, _) => Text('Error', style: TextStyle(color: cs.error, fontSize: 13)),
                data: (balance) => Text(
                  '₹${_fmt(balance)}',
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: balance >= 0 ? cs.onSurface : cs.error,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (txs) {
              if (txs.isEmpty) {
                return Center(
                  child: Text('No transactions in this month',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: cs.onSurfaceVariant,
                          )),
                );
              }

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
                  Expanded(
                    child: ListView.separated(
                      itemCount: txs.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 56),
                      itemBuilder: (ctx, i) {
                        final tx = txs[i];
                        final isIncome = tx.kind == 'income' || tx.kind == 'transfer_in';
                        final isTransfer = tx.kind.startsWith('transfer');
                        return ListTile(
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
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}
