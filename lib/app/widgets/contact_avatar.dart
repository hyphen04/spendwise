import 'dart:io';

import 'package:flutter/material.dart';

/// Shared avatar for a Dues contact.
///
/// Renders the cached device-contact photo (a `FileImage`) when `photoPath`
/// points to an existing file, and falls back to the emoji-on-tinted-circle
/// style used everywhere else in Dues otherwise. The tint is the contact's
/// `color` hex (e.g. `#E91E63`) at low alpha — the same treatment the detail
/// and list screens already used inline, now factored out so the photo-vs-emoji
/// fallback lives in one place.
class ContactAvatar extends StatelessWidget {
  const ContactAvatar({
    super.key,
    required this.photoPath,
    required this.emoji,
    required this.colorHex,
    required this.size,
    this.emojiFontSize,
  });

  /// App-local path to a cached contact photo, or null/empty for emoji-only.
  final String? photoPath;

  /// Fallback emoji (e.g. '👤').
  final String emoji;

  /// Contact color hex like `#E91E63` — used for the emoji-fallback tint.
  final String colorHex;

  /// Circle diameter in logical pixels.
  final double size;

  /// Emoji font size; defaults to `size * 0.5`.
  final double? emojiFontSize;

  Color get _tint {
    final hex = colorHex.replaceFirst('#', '0xFF');
    return Color(int.parse(hex)).withValues(alpha: 0.15);
  }

  bool get _hasPhoto {
    final p = photoPath;
    if (p == null || p.isEmpty) return false;
    return File(p).existsSync();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasPhoto) {
      return CircleAvatar(
        radius: size / 2,
        backgroundImage: FileImage(File(photoPath!)),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _tint,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        emoji,
        style: TextStyle(fontSize: emojiFontSize ?? size * 0.5),
      ),
    );
  }
}