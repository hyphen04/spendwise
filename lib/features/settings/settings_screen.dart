import 'dart:io';
import 'package:drift/drift.dart' show Value;
import '../../data/db/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../app/widgets/mono_numpad.dart';
import '../../app/widgets/screen_header.dart';
import '../../services/biometric_service.dart';
import '../../services/secure_storage_service.dart';
import '../../state/database_provider.dart';
import '../../state/prefs_providers.dart';
import 'update_sheet.dart';
import 'changelog_sheet.dart';
import '../reports/export/export_service.dart';
import '../reports/import/import_service.dart';
import 'manage_backups_screen.dart';
import 'sheets/feedback_sheet.dart';

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

  // ── Backup Quota Picker ──────────────────────────────────────────────────────

  static const _quotaOptions = [
    (10, '10 MB'),
    (20, '20 MB'),
    (50, '50 MB'),
    (100, '100 MB'),
    (500, '500 MB'),
    (-1, 'Unlimited'),
  ];

  String _quotaLabel(int mb) {
    for (final q in _quotaOptions) {
      if (q.$1 == mb) return q.$2;
    }
    return '$mb MB';
  }

  Future<void> _pickBackupQuota() async {
    final current = ref.read(prefsServiceProvider).backupQuotaMb;
    final choice = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Backup Storage Quota'),
        children: _quotaOptions
            .map((q) => ListTile(
                  title: Text(q.$2),
                  trailing: q.$1 == current
                      ? Icon(Icons.check_rounded,
                          color: Theme.of(ctx).colorScheme.primary)
                      : null,
                  onTap: () => Navigator.pop(ctx, q.$1),
                ))
            .toList(),
      ),
    );
    if (choice != null) {
      await ref.read(prefsServiceProvider).setBackupQuotaMb(choice);
      if (mounted) setState(() {});
    }
  }



  void _showColorPicker(BuildContext context, WidgetRef ref) {
    final currentColor = ref.read(themeSeedColorProvider);
    final colors = [
      0xFF0A0A0A, // Monochrome (Black)
      0xFF4F46E5, // Indigo
      0xFF10B981, // Emerald
      0xFFF43F5E, // Rose
      0xFFF59E0B, // Amber
      0xFF06B6D4, // Cyan
      0xFF8B5CF6, // Violet
    ];

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Select Primary Color', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: colors.map((color) {
                  final isSelected = color == currentColor;
                  // The Monochrome swatch is black in light mode and white
                  // in dark mode — otherwise the black dot vanishes against
                  // the dark bottom-sheet background. (The theme itself
                  // routes dark seeds to a light primary at runtime, so
                  // picking "Monochrome" in dark mode still gives a
                  // readable white-on-dark button — the swatch just needs
                  // to preview that same color.)
                  final isMonochrome = color == 0xFF0A0A0A;
                  final swatchColor = isMonochrome && isDark
                      ? const Color(0xFFF5F5F5)
                      : Color(color);
                  // Check icon: white on dark swatches, black on light swatches.
                  final iconColor = isMonochrome && isDark
                      ? Colors.black
                      : Colors.white;

                  return GestureDetector(
                    onTap: () {
                      ref.read(themeSeedColorProvider.notifier).set(color);
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: swatchColor,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 3)
                            : null,
                      ),
                      child: isSelected ? Icon(Icons.check, color: iconColor) : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // ── Clear data ───────────────────────────────────────────────────────────────

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 32),
        title: const Text('Erase all data?', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: const Text(
            'This deletes all transactions, dues, and budgets, and resets account balances to zero. '
            'Your accounts, categories, and modes are kept. This cannot be undone.',
            style: TextStyle(color: Colors.red)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Erase All', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final db = ref.read(appDatabaseProvider);
    await db.transaction(() async {
      await db.delete(db.transactions).go();
      await db.delete(db.transactionTags).go();
      await db.delete(db.dueEntries).go();
      await db.delete(db.dueSettlements).go();
      await db.delete(db.dueContacts).go();
      await db.delete(db.budgets).go();
      await db.update(db.accounts).write(
          const AccountsCompanion(openingBalance: Value(0.0)));
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
          const ScreenHeader(
            title: 'settings',
            subtitle: 'Preferences & app control',
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [

          // ── General ──────────────────────────────────────────────────────────
          _sectionHeader('General', context),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text('Accounts, Categories & More'),
                  subtitle: const Text('Manage your accounts, categories, modes & budgets'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/manage'),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Quick Dues Widget'),
                  subtitle: const Text('Show quick dues entry on home screen'),
                  secondary: const Icon(Icons.flash_on_rounded),
                  value: ref.watch(showQuickDuesProvider),
                  onChanged: (v) => ref.read(showQuickDuesProvider.notifier).set(v),
                ),
              ],
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
                const Divider(height: 1),
                ListTile(
                  title: const Text('Primary Color'),
                  subtitle: const Text('Choose your app theme color'),
                  leading: const Icon(Icons.palette_outlined),
                  trailing: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Color(ref.watch(themeSeedColorProvider)),
                      shape: BoxShape.circle,
                    ),
                  ),
                  onTap: () => _showColorPicker(context, ref),
                ),
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
                  subtitle: const Text('Generate reports as PDF, CSV, or Excel'),
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
                  subtitle: const Text('Restore records from external files'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    final db = ref.read(appDatabaseProvider);
                    ImportService.showImportSheet(context, db);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.backup_rounded),
                  title: const Text('Auto-Backups'),
                  subtitle: const Text('View and restore automated local backups'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ManageBackupsScreen()),
                    );
                  },
                ),

                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.sd_storage_outlined),
                  title: const Text('Backup Storage Limit'),
                  subtitle: const Text('Control how much space backups use'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _quotaLabel(
                            ref.read(prefsServiceProvider).backupQuotaMb),
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                  onTap: _pickBackupQuota,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  title: const Text('Erase All Data', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Permanently delete all your records', style: TextStyle(color: Colors.red)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.red),
                  onTap: _clearAllData,
                ),
                if (kDebugMode) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.bug_report_rounded, color: cs.error),
                    title: Text('DEBUG: Corrupt Database', style: TextStyle(color: cs.error)),
                    subtitle: const Text('Intentionally overwrite the DB with garbage to test Recovery flow. You must restart the app after.'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Corrupt DB?'),
                          content: const Text('This will destroy expenses.db!'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Destroy')),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                      final dbFolder = await getApplicationDocumentsDirectory();
                      final dbFile = File(p.join(dbFolder.path, 'expenses.db'));
                      await dbFile.writeAsString('I AM A CORRUPTED GARBAGE FILE AND NOT A SQLITE DATABASE!!');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Database Corrupted! Restart the app.')));
                      }
                    },
                  ),
                ],
              ],
            ),
          ),

          // ── Support & Updates ───────────────────────────────────────────────
          _sectionHeader('Support & Updates', context),
          Card(
            child: Column(
              children: [
                if (Platform.isAndroid) ...[
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
                    onTap: () => showUpdateSheet(
                      context: context,
                      currentVersion: _appVersion,
                    ),
                  ),
                  const Divider(height: 1),
                ],
                ListTile(
                  leading: const Icon(Icons.new_releases_outlined),
                  title: const Text("What's New"),
                  subtitle: const Text('Changelog for this version'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () =>
                      showWhatsNewSheet(context, version: _appVersion),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('Send Feedback'),
                  subtitle: const Text('Report bugs or request features'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showFeedbackSheet(context),
                ),
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
  static const _appGithubUrl = 'https://github.com/hyphen04/spendwise';
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
      children: [
        Material(
          color: cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const SizedBox(height: 32),
              // ── Logo ──
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    )
                  ]
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/logo/logo.png',
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // ── App Name & Version ──
              Text(
                'SpendWise',
                style: tt.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: cs.onSurface,
                ),
              ),
              if (_version.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'v$_version',
                    style: tt.labelLarge?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              
              const SizedBox(height: 16),
              
              // ── Description ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Finally, an app that tells you exactly where your money went. '
                  'Offline, private, and ad-free.',
                  textAlign: TextAlign.center,
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              const Divider(height: 1),
              
              // ── App GitHub ──
              InkWell(
                onTap: () => _launch(context, _appGithubUrl),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.code_rounded, color: cs.onPrimaryContainer, size: 22),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Open Source', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text('github.com/hyphen04/spendwise', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios_rounded, size: 14, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
              
              const Divider(height: 1),
              
              // ── Developer ──
              InkWell(
                onTap: () => _launch(context, _portfolioUrl),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.person_outline_rounded, color: cs.onSecondaryContainer, size: 22),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Designed & Developed by', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text('Kunj Patel (kunj.dev)', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios_rounded, size: 14, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        Center(
          child: Text(
            'Made with ☕ and questionable life choices',
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
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
