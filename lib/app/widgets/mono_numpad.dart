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
    this.keySize = 72,
    this.verticalSpacing = 6,
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
  /// bottom-right is a black check key and the bottom-left stays as the
  /// decimal point; the amount-entry sheet surfaces a separate backspace
  /// button next to the amount display in that mode. Otherwise the
  /// bottom-right is the backspace.
  final NumpadAction bottomRightAction;

  final bool confirmEnabled;
  final double keySize;
  final double verticalSpacing;

  @override
  Widget build(BuildContext context) {
    final confirmMode = bottomRightAction == NumpadAction.confirm;

    // 3-column grid. Bottom row layout depends on mode:
    //  - confirm mode (amount entry): `.` / `0` / ✓
    //  - non-confirm mode (PIN):     blank / `0` / ⌫
    // The backspace still has to be reachable when entering an amount — the
    // amount-entry sheet surfaces it as a small icon next to the big
    // amount display, so the numpad itself stays a clean 3×4 grid.
    final Widget bottomLeft = showDecimal
        ? _DigitKey(label: '.', onTap: () => onDigit('.'), keySize: keySize)
        : _BlankKey(keySize: keySize);

    final Widget bottomRight = confirmMode
        ? _ConfirmKey(
            enabled: confirmEnabled,
            onTap: confirmEnabled ? onConfirm : null,
            keySize: keySize,
          )
        : _ActionKey(
            icon: Icons.backspace_outlined,
            onTap: onBackspace,
            keySize: keySize,
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(['1', '2', '3']),
        _row(['4', '5', '6']),
        _row(['7', '8', '9']),
        _row3(bottomLeft, bottomRight),
      ],
    );
  }

  Widget _row(List<String> digits) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalSpacing),
      child: Row(
        children: digits
            .map((d) => Expanded(
                  child: Center(
                    child: _DigitKey(label: d, onTap: () => onDigit(d), keySize: keySize),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _row3(Widget left, Widget right) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalSpacing),
      child: Row(
        children: [
          Expanded(child: Center(child: left)),
          Expanded(
            child: Center(
              child: _DigitKey(label: '0', onTap: () => onDigit('0'), keySize: keySize),
            ),
          ),
          Expanded(child: Center(child: right)),
        ],
      ),
    );
  }
}

class _DigitKey extends StatelessWidget {
  const _DigitKey({required this.label, required this.onTap, required this.keySize});
  final String label;
  final VoidCallback onTap;
  final double keySize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _KeyShell(
      onTap: onTap,
      color: cs.surfaceContainer,
      keySize: keySize,
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: keySize * 0.36,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
        ),
      ),
    );
  }
}

class _ActionKey extends StatelessWidget {
  const _ActionKey({required this.icon, required this.onTap, required this.keySize});
  final IconData icon;
  final VoidCallback onTap;
  final double keySize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _KeyShell(
      onTap: onTap,
      color: Colors.transparent,
      keySize: keySize,
      child: Icon(icon, size: keySize * 0.33, color: cs.onSurface),
    );
  }
}

class _ConfirmKey extends StatelessWidget {
  const _ConfirmKey({required this.enabled, required this.onTap, required this.keySize});
  final bool enabled;
  final VoidCallback? onTap;
  final double keySize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _KeyShell(
      onTap: onTap,
      color: enabled ? cs.primary : cs.surfaceContainerHigh,
      keySize: keySize,
      child: Icon(
        Icons.check_rounded,
        size: keySize * 0.38,
        color: enabled ? cs.onPrimary : cs.onSurfaceVariant,
      ),
    );
  }
}

class _BlankKey extends StatelessWidget {
  const _BlankKey({required this.keySize});
  final double keySize;
  
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: keySize, height: keySize);
}

class _KeyShell extends StatelessWidget {
  const _KeyShell({
    required this.child,
    required this.color,
    required this.onTap,
    required this.keySize,
  });
  final Widget child;
  final Color color;
  final VoidCallback? onTap;
  final double keySize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: keySize,
      height: keySize,
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
