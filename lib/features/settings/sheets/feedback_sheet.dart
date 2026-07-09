import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> showFeedbackSheet(BuildContext context) async {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _FeedbackSheet(),
  );
}

enum _FallbackAction { github, copy, cancel }

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet();

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String _type = 'Bug';
  bool _submitting = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    final type = _type;
    final title = _titleCtrl.text.trim();
    final description = _descCtrl.text.trim();

    String? appVersion;
    String? deviceInfo;

    try {
      final pkg = await PackageInfo.fromPlatform();
      appVersion = '${pkg.version}+${pkg.buildNumber}';
      deviceInfo = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';

      final body = {
        'type': type,
        'title': title,
        'description': description,
        'appVersion': appVersion,
        'deviceInfo': deviceInfo,
      };

      final apiUrl = dotenv.env['FEEDBACK_API_URL'] ?? 'https://your-worker.workers.dev/';

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Feedback submitted! Thank you.')),
        );
        Navigator.pop(context);
      } else if (response.statusCode == 400) {
        _showError('Validation Error: ${response.body}');
      } else if (response.statusCode == 405) {
        _showError('Method Not Allowed: Check endpoint configuration.');
      } else if (response.statusCode == 429 ||
          (response.statusCode >= 500 && response.statusCode < 600)) {
        // API is out of limit or otherwise unavailable — offer the GitHub
        // issues page as a public fallback.
        await _showApiLimitFallback(
          type: type,
          title: title,
          description: description,
          appVersion: appVersion,
          deviceInfo: deviceInfo,
        );
      } else {
        _showError('Server Error (${response.statusCode}): ${response.body}');
      }
    } on TimeoutException {
      if (mounted) {
        await _showApiLimitFallback(
          type: type,
          title: title,
          description: description,
          appVersion: appVersion ?? 'unknown',
          deviceInfo: deviceInfo ?? 'unknown',
        );
      }
    } catch (_) {
      if (mounted) {
        await _showApiLimitFallback(
          type: type,
          title: title,
          description: description,
          appVersion: appVersion ?? 'unknown',
          deviceInfo: deviceInfo ?? 'unknown',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _showApiLimitFallback({
    required String type,
    required String title,
    required String description,
    required String appVersion,
    required String deviceInfo,
  }) async {
    final result = await showDialog<_FallbackAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.cloud_off_rounded,
          color: Theme.of(ctx).colorScheme.error,
        ),
        title: const Text('Feedback service unavailable'),
        content: const Text(
          'The feedback service is currently at its daily limit or temporarily unavailable.\n\n'
          'You can submit your feedback directly on our GitHub issues page instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _FallbackAction.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _FallbackAction.copy),
            child: const Text('Copy feedback'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, _FallbackAction.github),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open GitHub Issue'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (result == _FallbackAction.github) {
      await _openGitHubIssue(
        type: type,
        title: title,
        description: description,
        appVersion: appVersion,
        deviceInfo: deviceInfo,
      );
    } else if (result == _FallbackAction.copy) {
      await Clipboard.setData(ClipboardData(
        text: _formatFeedback(
          type: type,
          title: title,
          description: description,
          appVersion: appVersion,
          deviceInfo: deviceInfo,
        ),
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Feedback copied to clipboard')),
        );
      }
    }
  }

  Future<void> _openGitHubIssue({
    required String type,
    required String title,
    required String description,
    required String appVersion,
    required String deviceInfo,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final body = _formatFeedback(
      type: type,
      title: title,
      description: description,
      appVersion: appVersion,
      deviceInfo: deviceInfo,
    );
    final uri = Uri(
      scheme: 'https',
      host: 'github.com',
      path: '/hyphen04/spendwise/issues/new',
      queryParameters: {'title': title, 'body': body},
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await Clipboard.setData(ClipboardData(text: uri.toString()));
      messenger.showSnackBar(
        const SnackBar(content: Text('Link copied to clipboard')),
      );
    }
  }

  String _formatFeedback({
    required String type,
    required String title,
    required String description,
    required String appVersion,
    required String deviceInfo,
  }) {
    return '$description\n\n---\n\n'
        '**Type:** $type  \n'
        '**App version:** $appVersion  \n'
        '**Device:** $deviceInfo';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Send Feedback',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Let us know what you think, report a bug, or request a feature.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),

                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Feedback Type'),
                  items: ['Bug', 'Feature Request', 'UI/UX Issue', 'Performance', 'Other']
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setState(() => _type = v!),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'Short summary of the issue',
                  ),
                  maxLength: 200,
                  validator: (v) {
                    final text = v?.trim() ?? '';
                    if (text.length < 3) return 'Title must be at least 3 characters.';
                    return null;
                  },
                ),
                const SizedBox(height: 8),

                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Full details of what happened or what you want...',
                  ),
                  maxLines: 5,
                  minLines: 3,
                  maxLength: 5000,
                  validator: (v) {
                    final text = v?.trim() ?? '';
                    if (text.length < 5) return 'Description must be at least 5 characters.';
                    return null;
                  },
                ),
                const SizedBox(height: 8),

                const SizedBox(height: 24),

                SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text(
                            'Submit',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
