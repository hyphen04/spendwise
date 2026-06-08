import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/database_backup_service.dart';
import '../../state/database_provider.dart';

class ManageBackupsScreen extends ConsumerStatefulWidget {
  const ManageBackupsScreen({super.key});

  @override
  ConsumerState<ManageBackupsScreen> createState() => _ManageBackupsScreenState();
}

class _ManageBackupsScreenState extends ConsumerState<ManageBackupsScreen> {
  List<File>? _backups;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    setState(() => _loading = true);
    final backups = await DatabaseBackupService.getBackups();
    if (!mounted) return;
    setState(() {
      _backups = backups;
      _loading = false;
    });
  }

  Future<void> _restoreBackup(File backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.warning_amber_rounded, color: cs.error, size: 48),
          title: const Text('Restore Database?'),
          content: const Text(
            'This will overwrite your entire current database with this backup replica. '
            'Any changes made since this backup was created will be permanently lost.\n\n'
            'The app will freeze and you will need to manually restart it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
              ),
              child: const Text('Overwrite & Restore'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    if (!mounted) return;
    // Show restoring state
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    // Give UI time to update
    await Future.delayed(const Duration(milliseconds: 500));

    final db = ref.read(appDatabaseProvider);
    await DatabaseBackupService.restoreBackup(backup, db: db);

    if (!mounted) return;
    
    // Close loading dialog
    Navigator.pop(context);

    // Show "Must Restart" blocker dialog that cannot be dismissed
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            icon: const Icon(Icons.check_circle_outline, color: Colors.green, size: 48),
            title: const Text('Restore Complete'),
            content: const Text(
              'The backup replica has been successfully copied into place. '
              'To avoid data corruption and reload the app safely, you must now close it.\n\n'
              'Please swipe this app away from your recent apps and open it again.',
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  // Attempt graceful exit on Android (discouraged on iOS but usually works)
                  SystemNavigator.pop();
                },
                child: const Text('Exit App'),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _formatDate(DateTime dt) {
    final year = dt.year;
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Replicas'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _backups == null || _backups!.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.storage_rounded, size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                      const SizedBox(height: 16),
                      Text(
                        'No backups found',
                        style: TextStyle(
                          fontSize: 18,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Backups are created automatically\nwhen the app starts.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _backups!.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final backup = _backups![index];
                    final stat = backup.statSync();
                    final size = _formatSize(stat.size);
                    final date = _formatDate(stat.modified);

                    return Card(
                      elevation: 0,
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.backup_rounded, color: cs.primary),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Replica • $date',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$size • File: ${backup.path.split('/').last}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () {
                                    Share.shareXFiles([XFile(backup.path)]);
                                  },
                                  icon: const Icon(Icons.ios_share_outlined, size: 18),
                                  label: const Text('Export File'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.icon(
                                  onPressed: () => _restoreBackup(backup),
                                  icon: const Icon(Icons.restore_rounded, size: 18),
                                  label: const Text('Restore'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: cs.primaryContainer,
                                    foregroundColor: cs.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
