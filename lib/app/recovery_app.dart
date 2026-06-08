import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/database_backup_service.dart';

class RecoveryApp extends StatelessWidget {
  const RecoveryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SpendWise Recovery',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const _RecoveryScreen(),
    );
  }
}

class _RecoveryScreen extends StatefulWidget {
  const _RecoveryScreen();

  @override
  State<_RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<_RecoveryScreen> {
  List<File>? _backups;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    final backups = await DatabaseBackupService.getBackups();
    if (mounted) {
      setState(() {
        _backups = backups;
        _loading = false;
      });
    }
  }

  Future<void> _restore(File backup) async {
    // Show restoring state
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    await Future.delayed(const Duration(milliseconds: 500));

    // Because Drift DB failed to init, there is no open connection to close.
    // We can just safely copy it over directly!
    await DatabaseBackupService.restoreBackup(backup);

    if (!mounted) return;
    
    // Close loading dialog
    Navigator.pop(context);

    // Show completion dialog
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
              'The backup replica has been successfully copied into place.\n\n'
              'Please swipe this app away from your recent apps and open it again.',
            ),
            actions: [
              FilledButton(
                onPressed: () {
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
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Database Recovery'),
        backgroundColor: cs.errorContainer,
        foregroundColor: cs.onErrorContainer,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: cs.errorContainer,
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    children: [
                      Icon(Icons.running_with_errors_rounded, size: 64, color: cs.error),
                      const SizedBox(height: 16),
                      Text(
                        'Database Corrupted',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: cs.onErrorContainer,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'We detected that your main database file is malformed or corrupted. '
                        'To fix this, you can safely restore from one of your recent replicas below.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onErrorContainer, fontSize: 16),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _backups == null || _backups!.isEmpty
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
                                'Please contact support.',
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
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: Icon(Icons.backup_rounded, color: cs.primary),
                                title: Text(
                                  'Replica • $date',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  '$size • File: ${backup.path.split('/').last}',
                                ),
                                trailing: FilledButton.icon(
                                  onPressed: () => _restore(backup),
                                  icon: const Icon(Icons.restore_rounded, size: 18),
                                  label: const Text('Restore'),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
