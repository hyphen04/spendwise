import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/db/app_database.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../state/manage_providers.dart';
import '../../../state/prefs_providers.dart';
import '../sheets/account_form_sheet.dart';
import '../widgets/entity_tile.dart';

class AccountsTab extends ConsumerWidget {
  const AccountsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = ref.watch(accountsStreamProvider);

    return Scaffold(
      body: stream.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (accounts) => accounts.isEmpty
            ? _EmptyState(
                icon: '🏦',
                message: 'No accounts yet',
                onAdd: () => showAccountFormSheet(context),
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: accounts.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                itemBuilder: (ctx, i) => _AccountTile(account: accounts[i]),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_accounts',
        onPressed: () => showAccountFormSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _AccountTile extends ConsumerWidget {
  const _AccountTile({required this.account});
  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(accountsRepositoryProvider);
    final currencySymbol = _currencySymbol(account.currency);
    final defaultAccountId = ref.watch(defaultAccountIdProvider);
    final isDefault = account.id == defaultAccountId;
    final netBalanceAsync = ref.watch(accountNetBalanceProvider(account));
    final netBalance = netBalanceAsync.valueOrNull ?? account.openingBalance;

    return EntityTile(
      icon: account.icon,
      name: account.name,
      colorHex: account.color,
      subtitle:
          '$currencySymbol ${netBalance.toStringAsFixed(2)} · ${account.currency}',
      isDefault: isDefault,
      onEdit: () => showAccountFormSheet(context, editing: account),
      onArchive: () => _confirmArchive(context, repo, account),
      onDelete: () => _handleDelete(context, ref, repo, account),
      onSetDefault: () =>
          ref.read(defaultAccountIdProvider.notifier).set(account.id),
      onClearDefault: () =>
          ref.read(defaultAccountIdProvider.notifier).set(null),
    );
  }

  Future<void> _confirmArchive(
    BuildContext context,
    AccountsRepository repo,
    Account account,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Archive Account'),
        content: Text(
            'Archive "${account.name}"? It will be hidden from pickers but transactions are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Archive')),
        ],
      ),
    );
    if (ok == true) await repo.archive(account.id);
  }

  Future<void> _handleDelete(
    BuildContext context,
    WidgetRef ref,
    AccountsRepository repo,
    Account account,
  ) async {
    final count = await repo.countTransactions(account.id);
    if (!context.mounted) return;

    if (count == 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete Account'),
          content: Text('Permanently delete "${account.name}"?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok == true) await repo.reassignAndDelete(account.id, account.id);
      return;
    }

    // Has transactions — must reassign
    final allAccounts = await repo.getAllActive();
    if (!context.mounted) return;
    final others = allAccounts.where((a) => a.id != account.id).toList();

    if (others.isEmpty) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Cannot Delete'),
          content: Text(
              '"${account.name}" has $count transaction(s). Create another account first, then reassign.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    Account? target;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Reassign & Delete'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '"${account.name}" has $count transaction(s).\nMove them to:'),
              const SizedBox(height: 12),
              DropdownButton<Account>(
                isExpanded: true,
                value: target,
                hint: const Text('Select account'),
                items: others
                    .map((a) => DropdownMenuItem(
                          value: a,
                          child: Text('${a.icon} ${a.name}'),
                        ))
                    .toList(),
                onChanged: (v) => setSt(() => target = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed:
                  target == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('Reassign & Delete'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && target != null) {
      await repo.reassignAndDelete(account.id, target!.id);
    }
  }
}

String _currencySymbol(String currency) {
  const map = {'INR': '₹', 'USD': '\$', 'EUR': '€', 'GBP': '£', 'JPY': '¥'};
  return map[currency] ?? currency;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.message,
    required this.onAdd,
  });
  final String icon;
  final String message;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          Text(message,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
