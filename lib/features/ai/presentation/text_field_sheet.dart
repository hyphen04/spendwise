import 'package:flutter/material.dart';

/// Generic single-field bottom-sheet form used by the AI settings entries
/// (base URL, manual model name). The [controller] is **owned by the caller**
/// and reused across builds, so this widget does not dispose it — the caller
/// is responsible for its lifecycle.
///
/// Extracted from `ai_settings_section.dart` so the model picker's "use a
/// custom model name" fallback can reuse the same sheet.
class TextFieldSheet extends StatefulWidget {
  const TextFieldSheet({
    super.key,
    required this.title,
    required this.label,
    required this.controller,
    required this.helper,
    required this.onSaved,
  });

  final String title;
  final String label;
  final TextEditingController controller;
  final String helper;
  final ValueChanged<String> onSaved;

  @override
  State<TextFieldSheet> createState() => _TextFieldSheetState();
}

class _TextFieldSheetState extends State<TextFieldSheet> {
  @override
  void dispose() {
    // Controller is owned by the caller (reused across builds); don't dispose.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: widget.controller,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: widget.label,
                helperText: widget.helper,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    widget.onSaved(widget.controller.text.trim());
                    Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}