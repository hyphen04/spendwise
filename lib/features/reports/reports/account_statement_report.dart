import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/db/app_database.dart';

import '../../../state/manage_providers.dart';
import '../../../state/reports_providers.dart';


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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accsAsync = ref.watch(accountsStreamProvider);
    final from = DateTime(widget.year, widget.month).toIso8601String();
    final to = DateTime(widget.year, widget.month + 1).toIso8601String();
    final monthLabel = '${_months[widget.month - 1]} ${widget.year}';

    final accounts = (accsAsync.valueOrNull ?? <Account>[])
        .where((a) => !a.isArchived)
        .toList();

    if (_accountId == null && accounts.isNotEmpty) {
      _accountId = accounts.first.id;
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Account Statement', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            Text(monthLabel, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
      body: Column(
        children: [
          // Account picker
          if (accounts.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: DropdownButtonFormField<String>(
                initialValue: _accountId,
                decoration:
                    const InputDecoration(labelText: 'Account'),
                items: accounts
                    .map((a) => DropdownMenuItem(
                          value: a.id,
                          child: Text('${a.icon} ${a.name}'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _accountId = v),
              ),
            ),
          const SizedBox(height: 8),
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
    final async =
        ref.watch(accountStatementProvider((accountId, from, to)));
    final catMap = {
      for (final c in ref.watch(categoriesStreamProvider).valueOrNull ?? [])
        c.id: c.name
    };
    final accsAsync = ref.watch(accountsStreamProvider);
    final account = (accsAsync.valueOrNull ?? <Account>[])
        .where((a) => a.id == accountId)
        .firstOrNull;
    final openingBalance = account?.openingBalance ?? 0.0;

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (txs) {
        if (txs.isEmpty) {
          return Center(
            child: Text('No transactions in this period',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                    )),
          );
        }

        double balance = openingBalance;
        for (final t in txs) {
          if (t.kind == 'income') {
            balance += t.amount;
          } else if (t.kind == 'expense') {
            balance -= t.amount;
          }
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
                    'Net: ${balance >= 0 ? '+' : ''}₹${_fmt(balance)}',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: balance >= 0
                            ? Theme.of(context).colorScheme.onSurface
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
                  final isIncome = tx.kind == 'income';
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: isIncome
                          ? Theme.of(context).colorScheme.onSurface.withAlpha(20)
                          : cs.errorContainer,
                      child: Text(
                        isIncome ? '↑' : '↓',
                        style: TextStyle(
                          color: isIncome
                              ? Theme.of(context).colorScheme.onSurface
                              : cs.onErrorContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    title: Text(
                        catMap[tx.categoryId] ?? tx.kind,
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
                              ? Theme.of(context).colorScheme.onSurface
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
    );
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}
