import 'package:flutter/material.dart';
import '../../services/update_service.dart';

enum UpdateDialogState {
  checking,
  upToDate,
  updateAvailable,
  downloading,
  readyToInstall,
  launching,
  error,
}

class UpdateCheckDialog extends StatefulWidget {
  const UpdateCheckDialog({super.key, required this.currentVersion});
  final String currentVersion;

  @override
  State<UpdateCheckDialog> createState() => _UpdateCheckDialogState();
}

class _UpdateCheckDialogState extends State<UpdateCheckDialog> {
  UpdateDialogState _state = UpdateDialogState.checking;
  UpdateInfo? _info;
  double _progress = 0;
  String? _downloadedPath;
  String? _errorMessage;
  // When true, Retry goes back to readyToInstall instead of re-checking GitHub.
  bool _canRetryInstall = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _state = UpdateDialogState.checking;
      _canRetryInstall = false;
    });
    try {
      final info = await UpdateService.checkForUpdate();
      if (!mounted) return;
      setState(() {
        _state = info == null
            ? UpdateDialogState.upToDate
            : UpdateDialogState.updateAvailable;
        _info = info;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = UpdateDialogState.error;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _download() async {
    setState(() {
      _state = UpdateDialogState.downloading;
      _progress = 0;
      _downloadedPath = null;
    });
    try {
      await for (final event in UpdateService.downloadApk(_info!)) {
        if (!mounted) return;
        setState(() => _progress = event.progress);
        if (event.filePath != null) _downloadedPath = event.filePath;
      }
      if (!mounted) return;
      setState(() => _state = UpdateDialogState.readyToInstall);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = UpdateDialogState.error;
        _errorMessage =
            'Download failed: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  Future<void> _install() async {
    if (_downloadedPath == null) return;

    setState(() => _state = UpdateDialogState.launching);
    final result = await UpdateService.installApk(_downloadedPath!);
    if (!mounted) return;

    switch (result) {
      case InstallResult.launched:
        // Give the system installer time to come to the foreground, then close.
        await Future.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        Navigator.of(context).pop();
        break;
      case InstallResult.permissionDenied:
        setState(() {
          _state = UpdateDialogState.error;
          _canRetryInstall = true;
          _errorMessage =
              'SpendWise needs permission to install apps.\n\n'
              'The Settings screen was just opened — find SpendWise and enable '
              '"Allow from this source", then come back and tap Retry.';
        });
        break;
      case InstallResult.fileNotFound:
        setState(() {
          _state = UpdateDialogState.updateAvailable;
          _downloadedPath = null;
          _errorMessage = null;
        });
        break;
      case InstallResult.error:
        setState(() {
          _state = UpdateDialogState.error;
          _canRetryInstall = false;
          _errorMessage =
              'The installer could not open the file. '
              'Try downloading again.';
        });
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final canDismiss = _state != UpdateDialogState.downloading &&
        _state != UpdateDialogState.launching;

    return PopScope(
      canPop: canDismiss,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(_titleIcon, size: 20, color: _titleColor(cs)),
            const SizedBox(width: 10),
            Text(_titleText,
                style:
                    tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        content: _buildContent(cs, tt),
        actions: _buildActions(cs, canDismiss),
      ),
    );
  }

  IconData get _titleIcon => switch (_state) {
        UpdateDialogState.checking => Icons.search_rounded,
        UpdateDialogState.upToDate => Icons.check_circle_outline_rounded,
        UpdateDialogState.updateAvailable => Icons.system_update_outlined,
        UpdateDialogState.downloading => Icons.download_rounded,
        UpdateDialogState.readyToInstall => Icons.install_mobile_outlined,
        UpdateDialogState.launching => Icons.launch_rounded,
        UpdateDialogState.error => Icons.error_outline_rounded,
      };

  String get _titleText => switch (_state) {
        UpdateDialogState.checking => 'Checking…',
        UpdateDialogState.upToDate => 'Up to date',
        UpdateDialogState.updateAvailable => 'Update available',
        UpdateDialogState.downloading => 'Downloading…',
        UpdateDialogState.readyToInstall => 'Ready to install',
        UpdateDialogState.launching => 'Opening installer…',
        UpdateDialogState.error => 'Something went wrong',
      };

  Color _titleColor(ColorScheme cs) => switch (_state) {
        UpdateDialogState.upToDate => const Color(0xFF16A34A),
        UpdateDialogState.error => cs.error,
        _ => cs.onSurface,
      };

  Widget _buildContent(ColorScheme cs, TextTheme tt) {
    return switch (_state) {
      UpdateDialogState.checking || UpdateDialogState.launching => const SizedBox(
          height: 48,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      UpdateDialogState.upToDate => Text(
          'You\'re on the latest version'
          '${widget.currentVersion.isNotEmpty ? ' (v${widget.currentVersion})' : ''}.',
          style: tt.bodyMedium,
        ),
      UpdateDialogState.updateAvailable => SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SpendWise v${_info!.version} is available.',
                style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (_info!.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      _info!.releaseNotes,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      UpdateDialogState.downloading => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${(_progress * 100).toInt()}%',
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: _progress,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Text(
              'Do not close the app…',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      UpdateDialogState.readyToInstall => Text(
          'SpendWise v${_info!.version} downloaded. Tap Install to continue.',
          style: tt.bodyMedium,
        ),
      UpdateDialogState.error => Text(
          _errorMessage ?? 'Something went wrong.',
          style: tt.bodyMedium?.copyWith(color: cs.error),
        ),
    };
  }

  List<Widget> _buildActions(ColorScheme cs, bool canDismiss) {
    return switch (_state) {
      UpdateDialogState.checking || UpdateDialogState.launching => [
          if (canDismiss)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
        ],
      UpdateDialogState.upToDate => [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Great'),
          ),
        ],
      UpdateDialogState.updateAvailable => [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: _download,
            child: const Text('Download & Install'),
          ),
        ],
      UpdateDialogState.downloading => [
          TextButton(
            onPressed: null,
            child: const Text('Cancel'),
          ),
        ],
      UpdateDialogState.readyToInstall => [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: _install,
            child: const Text('Install Now'),
          ),
        ],
      UpdateDialogState.error => [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: _canRetryInstall
                ? () => setState(() {
                      _state = UpdateDialogState.readyToInstall;
                      _canRetryInstall = false;
                      _errorMessage = null;
                    })
                : _check,
            child: const Text('Retry'),
          ),
        ],
    };
  }
}
