import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Action shown on the bottom-right key of the numpad.
enum NumpadAction { backspace, confirm }

/// A circular, monochrome numeric keypad (1–9, decimal, 0, action key).
///
/// Used by the amount-entry sheet, the lock screen, and the settings PIN
/// sheets. Digit keys are light-gray circles; the optional confirm key is a
/// solid black circle with a check icon.
class MonoNumpad extends StatelessWidget {
  const MonoNumpad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onConfirm,
    this.showDecimal = true,
    this.bottomRightAction = NumpadAction.backspace,
    this.confirmEnabled = true,
  });

  /// Called with the tapped digit character ('0'–'9').
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  /// Required when [bottomRightAction] is [NumpadAction.confirm].
  final VoidCallback? onConfirm;

  /// When true, the bottom-left key is a decimal point; otherwise blank
  /// (used by PIN entry, which has no decimals).
  final bool showDecimal;

  /// What the bottom-right key does. When [NumpadAction.confirm], the
  /// bottom-left becomes backspace and the bottom-right is a black check key.
  final NumpadAction bottomRightAction;

  final bool confirmEnabled;

  @override
  Widget build(BuildContext context) {
    final confirmMode = bottomRightAction == NumpadAction.confirm;

    // Bottom-left key:
    //  - confirm mode → backspace
    //  - otherwise → decimal point (or blank if disabled)
    final Widget bottomLeft = confirmMode
        ? _ActionKey(
            icon: Icons.backspace_outlined,
            onTap: onBackspace,
          )
        : (showDecimal
            ? _DigitKey(label: '.', onTap: () => onDigit('.'))
            : const _BlankKey());

    // Bottom-right key:
    final Widget bottomRight = confirmMode
        ? _ConfirmKey(
            enabled: confirmEnabled,
            onTap: confirmEnabled ? onConfirm : null,
          )
        : _ActionKey(
            icon: Icons.backspace_outlined,
            onTap: onBackspace,
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(['1', '2', '3']),
        _row(['4', '5', '6']),
        _row(['7', '8', '9']),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(child: Center(child: bottomLeft)),
              Expanded(
                child: Center(
                  child: _DigitKey(label: '0', onTap: () => onDigit('0')),
                ),
              ),
              Expanded(child: Center(child: bottomRight)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(List<String> digits) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: digits
            .map((d) => Expanded(
                  child: Center(
                    child: _DigitKey(label: d, onTap: () => onDigit(d)),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

const double _keySize = 72;

class _DigitKey extends StatelessWidget {
  const _DigitKey({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _KeyShell(
      onTap: onTap,
      color: cs.surfaceContainer,
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
        ),
      ),
    );
  }
}

class _ActionKey extends StatelessWidget {
  const _ActionKey({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _KeyShell(
      onTap: onTap,
      color: Colors.transparent,
      child: Icon(icon, size: 24, color: cs.onSurface),
    );
  }
}

class _ConfirmKey extends StatelessWidget {
  const _ConfirmKey({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _KeyShell(
      onTap: onTap,
      color: enabled ? cs.primary : cs.surfaceContainerHigh,
      child: Icon(
        Icons.check_rounded,
        size: 28,
        color: enabled ? cs.onPrimary : cs.onSurfaceVariant,
      ),
    );
  }
}

class _BlankKey extends StatelessWidget {
  const _BlankKey();
  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: _keySize, height: _keySize);
}

class _KeyShell extends StatelessWidget {
  const _KeyShell({
    required this.child,
    required this.color,
    required this.onTap,
  });
  final Widget child;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _keySize,
      height: _keySize,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onTap!();
                },
          child: Center(child: child),
        ),
      ),
    );
  }
}
