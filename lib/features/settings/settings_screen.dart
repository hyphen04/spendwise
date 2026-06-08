import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/widgets/mono_numpad.dart';
import '../../app/widgets/screen_header.dart';
import '../../services/biometric_service.dart';
import '../../services/secure_storage_service.dart';
import '../../state/database_provider.dart';
import '../../state/prefs_providers.dart';
import 'update_check_dialog.dart';
import '../reports/export/export_service.dart';
import '../reports/import/import_service.dart';

class SettingsScreenV2 extends ConsumerStatefulWidget {
  const SettingsScreenV2({super.key});

  @override
  ConsumerState<SettingsScreenV2> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreenV2> {
  bool _biometricAvailable = false;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    BiometricService.isAvailable()
        .then((v) { if (mounted) setState(() => _biometricAvailable = v); });
    PackageInfo.fromPlatform()
        .then((info) { if (mounted) setState(() => _appVersion = info.version); });
  }

  // ── PIN helpers ─────────────────────────────────────────────────────────────

  Future<bool> _showPinSetup(BuildContext context) async {
    return await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          isDismissible: false,
          enableDrag: false,
          builder: (_) => const _PinSetupSheet(),
        ) ??
        false;
  }

  Future<bool> _showPinVerify(BuildContext context, String title) async {
    return await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          isDismissible: false,
          enableDrag: false,
          builder: (_) => _PinVerifySheet(title: title),
        ) ??
        false;
  }

  // ── Lock toggle ──────────────────────────────────────────────────────────────

  Future<void> _onLockToggle(bool value) async {
    if (value) {
      final ok = await _showPinSetup(context);
      if (ok && mounted) {
        await ref.read(lockEnabledProvider.notifier).set(true);
      }
    } else {
      final hasPin = await SecureStorageService.hasPin();
      bool confirmed = true;
      if (hasPin && mounted) {
        confirmed = await _showPinVerify(context, 'Confirm to disable lock');
      }
      if (confirmed && mounted) {
        await SecureStorageService.clearPin();
        await ref.read(lockEnabledProvider.notifier).set(false);
      }
    }
  }

  // ── Change PIN ───────────────────────────────────────────────────────────────

  Future<void> _onChangePin() async {
    final verified = await _showPinVerify(context, 'Enter current PIN');
    if (!verified || !mounted) return;
    final ok = await _showPinSetup(context);
    if (ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('PIN updated')));
    }
  }

  // ── Timeout picker ───────────────────────────────────────────────────────────

  static const _timeoutOptions = [
    (0, 'Immediately'),
    (15, '15 seconds'),
    (30, '30 seconds'),
    (60, '1 minute'),
    (300, '5 minutes'),
    (900, '15 minutes'),
    (1800, '30 minutes'),
    (3600, '1 hour'),
  ];

  String _timeoutLabel(int seconds) {
    for (final t in _timeoutOptions) {
      if (t.$1 == seconds) return t.$2;
    }
    return '$seconds seconds';
  }

  Future<void> _pickTimeout() async {
    final current = ref.read(prefsServiceProvider).lockTimeoutSeconds;
    final choice = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Lock after'),
        children: _timeoutOptions
            .map((t) => ListTile(
                  title: Text(t.$2),
                  trailing: t.$1 == current
                      ? Icon(Icons.check_rounded,
                          color: Theme.of(ctx).colorScheme.primary)
                      : null,
                  onTap: () => Navigator.pop(ctx, t.$1),
                ))
            .toList(),
      ),
    );
    if (choice != null) {
      await ref.read(prefsServiceProvider).setLockTimeout(choice);
      if (mounted) setState(() {});
    }
  }

  // ── Clear data ───────────────────────────────────────────────────────────────

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all data?'),
        content: const Text(
            'This deletes all transactions and budgets. '
            'Accounts, categories, and modes are kept. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final db = ref.read(appDatabaseProvider);
    await db.transaction(() async {
      await db.delete(db.transactions).go();
      await db.delete(db.budgets).go();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All transaction data cleared')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final oledDark = ref.watch(oledDarkProvider);
    final lockEnabled = ref.watch(lockEnabledProvider);
    final biometricEnabled = ref.watch(biometricEnabledProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header (outside ListView so MediaQuery.padding.top is intact) ───
          const ScreenHeader(title: 'settings'),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [

          // ── Manage ──────────────────────────────────────────────────────────
          _sectionHeader('Manage', context),
          Card(
            child: ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: const Text('Accounts, Categories & More'),
              subtitle: const Text('Manage your accounts, categories, modes & budgets'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/manage'),
            ),
          ),

          // ── Appearance ──────────────────────────────────────────────────────
          _sectionHeader('Appearance', context),
          Card(
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Theme',
                            style: Theme.of(context).textTheme.bodyLarge),
                      ),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                              value: ThemeMode.system,
                              icon: Icon(Icons.brightness_auto_outlined),
                              label: Text('Auto')),
                          ButtonSegment(
                              value: ThemeMode.light,
                              icon: Icon(Icons.light_mode_outlined),
                              label: Text('Light')),
                          ButtonSegment(
                              value: ThemeMode.dark,
                              icon: Icon(Icons.dark_mode_outlined),
                              label: Text('Dark')),
                        ],
                        selected: {themeMode},
                        onSelectionChanged: (s) =>
                            ref.read(themeModeProvider.notifier).set(s.first),
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
                if (themeMode == ThemeMode.dark) ...[
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('OLED Dark'),
                    subtitle: const Text('Pure black background'),
                    secondary: const Icon(Icons.contrast_outlined),
                    value: oledDark,
                    onChanged: (v) =>
                        ref.read(oledDarkProvider.notifier).set(v),
                  ),
                ],
              ],
            ),
          ),

          // ── Security ────────────────────────────────────────────────────────
          _sectionHeader('Security', context),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('App Lock'),
                  subtitle: const Text('Require PIN or biometric to open'),
                  secondary: const Icon(Icons.lock_outline_rounded),
                  value: lockEnabled,
                  onChanged: _onLockToggle,
                ),
                if (lockEnabled) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.pin_outlined),
                    title: const Text('Change PIN'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _onChangePin,
                  ),
                  if (_biometricAvailable) ...[
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('Biometric Unlock'),
                      subtitle: const Text('Use Face ID or fingerprint'),
                      secondary: const Icon(Icons.fingerprint_rounded),
                      value: biometricEnabled,
                      onChanged: (v) =>
                          ref.read(biometricEnabledProvider.notifier).set(v),
                    ),
                  ],
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text('Lock after'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _timeoutLabel(
                              ref.read(prefsServiceProvider).lockTimeoutSeconds),
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                    onTap: _pickTimeout,
                  ),
                ],
              ],
            ),
          ),

          // ── Data ────────────────────────────────────────────────────────────
          _sectionHeader('Data', context),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.upload_outlined),
                  title: const Text('Export Data'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    final db = ref.read(appDatabaseProvider);
                    final now = DateTime.now();
                    ExportService.showExportSheet(context, db,
                        defaultFrom: DateTime(now.year, now.month).toIso8601String(),
                        defaultTo: DateTime(now.year, now.month + 1).toIso8601String());
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Import Data'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    final db = ref.read(appDatabaseProvider);
                    ImportService.showImportSheet(context, db);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded,
                      color: cs.error),
                  title: Text('Clear All Data',
                      style: TextStyle(color: cs.error)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _clearAllData,
                ),
              ],
            ),
          ),

          // ── About ────────────────────────────────────────────────────────────
          _sectionHeader('About', context),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('Version'),
                  trailing: Text(
                    _appVersion.isEmpty ? '…' : _appVersion,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                if (Platform.isAndroid) ...[
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.update_outlined),
                    title: const Text('Auto-check for updates'),
                    subtitle: const Text('Check on startup when connected'),
                    value: ref.watch(autoCheckUpdatesProvider),
                    onChanged: (v) =>
                        ref.read(autoCheckUpdatesProvider.notifier).set(v),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.system_update_outlined),
                    title: const Text('Check for Update'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => UpdateCheckDialog(
                        currentVersion: _appVersion,
                      ),
                    ),
                  ),
                ],
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: const Text('Open Source Licenses'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'SpendWise',
                      applicationVersion: _appVersion),
                ),
              ],
            ),
          ),
          // ── Made by ─────────────────────────────────────────────────────────
          const SizedBox(height: 32),
          const _AboutCard(),
          const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
      ),
    );
  }
}

// ── About / Made by card ──────────────────────────────────────────────────────

class _AboutCard extends StatefulWidget {
  const _AboutCard();

  @override
  State<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends State<_AboutCard> {
  static const _githubUrl = 'https://github.com/hyphen04';
  static const _portfolioUrl = 'https://kunj.dev';

  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform()
        .then((i) { if (mounted) setState(() => _version = i.version); });
  }

  Future<void> _launch(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await Clipboard.setData(ClipboardData(text: url));
      messenger.showSnackBar(
        const SnackBar(content: Text('Link copied to clipboard')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── App card ────────────────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/logo/logo.png',
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SpendWise',
                          style: tt.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Personal Finance',
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (_version.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'v$_version',
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Finally, an app that tells you exactly where your money went. '
                'You probably won\'t like the answer — but hey, at least it\'s offline so no one else can see your shame.',
                style: tt.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant, height: 1.55),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _StatCell(emoji: '📵', label: 'Offline', cs: cs, tt: tt),
                  const SizedBox(width: 8),
                  _StatCell(emoji: '🚫', label: 'No Ads', cs: cs, tt: tt),
                  const SizedBox(width: 8),
                  _StatCell(emoji: '🔒', label: 'Private', cs: cs, tt: tt),
                  const SizedBox(width: 8),
                  _StatCell(emoji: '💾', label: 'On-Device', cs: cs, tt: tt),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Developer card ──────────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: cs.primary,
                    child: Text(
                      'KP',
                      style: TextStyle(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Kunj Patel',
                          style: tt.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(
                        'Software Developer · Gujarat',
                        style: tt.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Builds software that respects the person using it. '
                'Currently questioning why he made an app that judges his own spending — '
                'but the code is clean, and that\'s what matters.',
                style: tt.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant, height: 1.55),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _LinkChip(
                    icon: Icons.code_rounded,
                    label: 'github.com/hyphen04',
                    onTap: () => _launch(context, _githubUrl),
                    cs: cs,
                  ),
                  const SizedBox(width: 8),
                  _LinkChip(
                    icon: Icons.language_rounded,
                    label: 'kunj.dev',
                    onTap: () => _launch(context, _portfolioUrl),
                    cs: cs,
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        Center(
          child: Text(
            'Made with ☕ and questionable life choices',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.emoji,
    required this.label,
    required this.cs,
    required this.tt,
  });

  final String emoji;
  final String label;
  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 5),
            Text(
              label,
              style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.cs,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outline),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: cs.onSurface),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── PIN Setup Sheet ───────────────────────────────────────────────────────────

class _PinSetupSheet extends StatefulWidget {
  const _PinSetupSheet();

  @override
  State<_PinSetupSheet> createState() => _PinSetupSheetState();
}

enum _PinSetupStep { enter, confirm }

class _PinSetupSheetState extends State<_PinSetupSheet> {
  _PinSetupStep _step = _PinSetupStep.enter;
  String _firstPin = '';
  final List<String> _digits = [];
  bool _error = false;

  void _onDigit(String d) {
    if (_digits.length >= 4) return;
    setState(() {
      _digits.add(d);
      _error = false;
    });
    if (_digits.length == 4) _onComplete();
  }

  void _onBackspace() {
    if (_digits.isEmpty) return;
    setState(() {
      _digits.removeLast();
      _error = false;
    });
  }

  Future<void> _onComplete() async {
    final pin = _digits.join();
    if (_step == _PinSetupStep.enter) {
      setState(() {
        _firstPin = pin;
        _digits.clear();
        _step = _PinSetupStep.confirm;
      });
    } else {
      if (pin == _firstPin) {
        await SecureStorageService.savePin(pin);
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(() {
          _digits.clear();
          _firstPin = '';
          _step = _PinSetupStep.enter;
          _error = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final prompt = _step == _PinSetupStep.enter
        ? 'Enter a new 4-digit PIN'
        : 'Confirm your PIN';
    return _PinSheet(
      title: 'Set PIN',
      prompt: prompt,
      digits: _digits,
      error: _error,
      errorText: 'PINs did not match — try again',
      onDigit: _onDigit,
      onBackspace: _onBackspace,
      onCancel: () => Navigator.pop(context, false),
    );
  }
}

// ── PIN Verify Sheet ──────────────────────────────────────────────────────────

class _PinVerifySheet extends StatefulWidget {
  const _PinVerifySheet({required this.title});
  final String title;

  @override
  State<_PinVerifySheet> createState() => _PinVerifySheetState();
}

class _PinVerifySheetState extends State<_PinVerifySheet> {
  final List<String> _digits = [];
  bool _error = false;

  void _onDigit(String d) {
    if (_digits.length >= 4) return;
    setState(() {
      _digits.add(d);
      _error = false;
    });
    if (_digits.length == 4) _verify();
  }

  void _onBackspace() {
    if (_digits.isEmpty) return;
    setState(() {
      _digits.removeLast();
      _error = false;
    });
  }

  Future<void> _verify() async {
    final ok = await SecureStorageService.verifyPin(_digits.join());
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _digits.clear();
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PinSheet(
      title: widget.title,
      prompt: 'Enter your PIN',
      digits: _digits,
      error: _error,
      errorText: 'Incorrect PIN',
      onDigit: _onDigit,
      onBackspace: _onBackspace,
      onCancel: () => Navigator.pop(context, false),
    );
  }
}

// ── Shared PIN Sheet UI ───────────────────────────────────────────────────────

class _PinSheet extends StatelessWidget {
  const _PinSheet({
    required this.title,
    required this.prompt,
    required this.digits,
    required this.error,
    required this.errorText,
    required this.onDigit,
    required this.onBackspace,
    required this.onCancel,
  });

  final String title;
  final String prompt;
  final List<String> digits;
  final bool error;
  final String errorText;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: tt.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                IconButton(
                    onPressed: onCancel,
                    icon: const Icon(Icons.close_rounded)),
              ],
            ),
            const SizedBox(height: 8),
            Text(prompt,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < digits.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled
                        ? (error ? cs.error : cs.primary)
                        : Colors.transparent,
                    border: Border.all(
                      color: error ? cs.error : cs.outline,
                      width: 2,
                    ),
                  ),
                );
              }),
            ),
            if (error) ...[
              const SizedBox(height: 10),
              Text(errorText,
                  style: tt.bodySmall?.copyWith(color: cs.error)),
            ] else
              const SizedBox(height: 26),
            const SizedBox(height: 12),
            MonoNumpad(
              onDigit: onDigit,
              onBackspace: onBackspace,
              showDecimal: false,
            ),
          ],
        ),
      ),
    );
  }
}
