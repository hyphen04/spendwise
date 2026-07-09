import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/widgets/changelog_markdown.dart';
import '../../services/update_service.dart';

/// Opens the SpendWise update sheet — checks GitHub for a newer release and,
/// if one exists, shows the rendered changelog with Download / Install actions.
/// Replaces the old [UpdateCheckDialog] with a roomier bottom sheet so the
/// "what's new" notes are readable.
Future<void> showUpdateSheet({
  required BuildContext context,
  required String currentVersion,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _UpdateSheet(currentVersion: currentVersion),
  );
}

enum _UpdateState {
  checking,
  upToDate,
  updateAvailable,
  downloading,
  readyToInstall,
  launching,
  error,
}

class _UpdateSheet extends StatefulWidget {
  const _UpdateSheet({required this.currentVersion});

  final String currentVersion;

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  _UpdateState _state = _UpdateState.checking;
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
      _state = _UpdateState.checking;
      _canRetryInstall = false;
    });
    try {
      final info = await UpdateService.checkForUpdate();
      if (!mounted) return;
      setState(() {
        _state = info == null
            ? _UpdateState.upToDate
            : _UpdateState.updateAvailable;
        _info = info;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _UpdateState.error;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _download() async {
    setState(() {
      _state = _UpdateState.downloading;
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
      setState(() => _state = _UpdateState.readyToInstall);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _UpdateState.error;
        _errorMessage =
            'Download failed: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  Future<void> _install() async {
    if (_downloadedPath == null) return;

    setState(() => _state = _UpdateState.launching);
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
          _state = _UpdateState.error;
          _canRetryInstall = true;
          _errorMessage =
              'SpendWise needs permission to install apps.\n\n'
              'The Settings screen was just opened — find SpendWise and enable '
              '"Allow from this source", then come back and tap Retry.';
        });
        break;
      case InstallResult.fileNotFound:
        setState(() {
          _state = _UpdateState.updateAvailable;
          _downloadedPath = null;
          _errorMessage = null;
        });
        break;
      case InstallResult.error:
        setState(() {
          _state = _UpdateState.error;
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
    final canDismiss = _state != _UpdateState.downloading &&
        _state != _UpdateState.launching;

    return PopScope(
      canPop: canDismiss,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              _buildHeader(cs, tt),
              const Divider(height: 1),
              Flexible(child: _buildBody(cs, tt)),
              _buildFooter(cs, canDismiss),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, TextTheme tt) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      child: Row(
        children: [
          Icon(_titleIcon, size: 22, color: _titleColor(cs)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _titleText,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _subtitle,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: (_state == _UpdateState.downloading ||
                    _state == _UpdateState.launching)
                ? null
                : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme cs, TextTheme tt) {
    return switch (_state) {
      _UpdateState.checking || _UpdateState.launching => Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: const CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      _UpdateState.upToDate => Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
            child: Text(
              'You\'re on the latest version'
              '${widget.currentVersion.isNotEmpty ? ' (v${widget.currentVersion})' : ''}.',
              style: tt.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      _UpdateState.updateAvailable => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: _info!.releaseNotes.isNotEmpty
              ? ChangelogMarkdown(source: _info!.releaseNotes)
              : Text(
                  'No release notes provided.',
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
        ),
      _UpdateState.downloading => Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${(_progress * 100).toInt()}%',
                style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _progress,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 12),
              Text(
                'Downloading update… do not close the app.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      _UpdateState.readyToInstall => Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
            child: Text(
              'SpendWise v${_info!.version} downloaded. Tap Install to continue.',
              style: tt.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      _UpdateState.error => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Text(
            _errorMessage ?? 'Something went wrong.',
            style: tt.bodyMedium?.copyWith(color: cs.error),
          ),
        ),
    };
  }

  Widget _buildFooter(ColorScheme cs, bool canDismiss) {
    final actions = _actions(canDismiss);
    if (actions.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: actions,
      ),
    );
  }

  List<Widget> _actions(bool canDismiss) {
    switch (_state) {
      case _UpdateState.checking:
      case _UpdateState.launching:
        return canDismiss
            ? [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ]
            : const [];
      case _UpdateState.upToDate:
        return [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Great'),
          ),
        ];
      case _UpdateState.updateAvailable:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _download,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Download & Install'),
          ),
        ];
      case _UpdateState.downloading:
        return [
          TextButton(
            onPressed: null,
            child: const Text('Cancel'),
          ),
        ];
      case _UpdateState.readyToInstall:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _install,
            icon: const Icon(Icons.install_mobile_outlined, size: 18),
            label: const Text('Install Now'),
          ),
        ];
      case _UpdateState.error:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _canRetryInstall
                ? () => setState(() {
                      _state = _UpdateState.readyToInstall;
                      _canRetryInstall = false;
                      _errorMessage = null;
                    })
                : _check,
            child: const Text('Retry'),
          ),
        ];
    }
  }

  // ── Header helpers ───────────────────────────────────────────────────────

  IconData get _titleIcon => switch (_state) {
        _UpdateState.checking => Icons.search_rounded,
        _UpdateState.upToDate => Icons.check_circle_outline_rounded,
        _UpdateState.updateAvailable => Icons.system_update_outlined,
        _UpdateState.downloading => Icons.download_rounded,
        _UpdateState.readyToInstall => Icons.install_mobile_outlined,
        _UpdateState.launching => Icons.launch_rounded,
        _UpdateState.error => Icons.error_outline_rounded,
      };

  String get _titleText => switch (_state) {
        _UpdateState.checking => 'Checking for updates',
        _UpdateState.upToDate => 'Up to date',
        _UpdateState.updateAvailable => 'Update available',
        _UpdateState.downloading => 'Downloading',
        _UpdateState.readyToInstall => 'Ready to install',
        _UpdateState.launching => 'Opening installer',
        _UpdateState.error => 'Something went wrong',
      };

  Color _titleColor(ColorScheme cs) => switch (_state) {
        _UpdateState.upToDate => const Color(0xFF16A34A),
        _UpdateState.error => cs.error,
        _ => cs.onSurface,
      };

  String get _subtitle {
    switch (_state) {
      case _UpdateState.updateAvailable:
        final size = _formatBytes(_info?.apkSize ?? 0);
        return size.isEmpty
            ? 'SpendWise v${_info!.version}'
            : 'SpendWise v${_info!.version} • $size';
      case _UpdateState.readyToInstall:
        return 'SpendWise v${_info!.version}';
      default:
        return '';
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    var d = bytes.toDouble();
    while (d >= 1024 && i < units.length - 1) {
      d /= 1024;
      i++;
    }
    final value = d >= 10 ? d.round().toString() : d.toStringAsFixed(1);
    return '$value ${units[i]}';
  }
}