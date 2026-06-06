import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app/widgets/mono_numpad.dart';
import '../../services/biometric_service.dart';
import '../../services/secure_storage_service.dart';
import '../../state/prefs_providers.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final List<String> _digits = [];
  bool _biometricAvailable = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    if (!ref.read(biometricEnabledProvider)) return;
    final available = await BiometricService.isAvailable();
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
    if (available) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) _tryBiometric();
    }
  }

  Future<void> _tryBiometric() async {
    final result = await BiometricService.authenticate();
    if (result && mounted) widget.onUnlocked();
  }

  void _onDigit(String d) {
    if (_digits.length >= 4) return;
    setState(() {
      _digits.add(d);
      _error = false;
    });
    if (_digits.length == 4) _verifyPin();
  }

  void _onBackspace() {
    if (_digits.isEmpty) return;
    setState(() {
      _digits.removeLast();
      _error = false;
    });
  }

  Future<void> _verifyPin() async {
    final pin = _digits.join();
    final ok = await SecureStorageService.verifyPin(pin);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() {
        _digits.clear();
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Wordmark
                Text(
                  'spendwise',
                  style: GoogleFonts.manrope(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                    letterSpacing: -1.0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Enter your PIN',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: cs.onSurfaceVariant,
                  ),
                ),

                const Spacer(),

                // PIN dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (i) {
                    final filled = i < _digits.length;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled ? cs.onSurface : Colors.transparent,
                        border: Border.all(
                          color: _error
                              ? cs.onSurface.withValues(alpha: 0.4)
                              : cs.outline,
                          width: 2,
                        ),
                      ),
                    );
                  }),
                ),
                if (_error) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Incorrect PIN',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ] else
                  const SizedBox(height: 26),

                const Spacer(),

                // Circular MonoNumpad
                MonoNumpad(
                  onDigit: _onDigit,
                  onBackspace: _onBackspace,
                  showDecimal: false,
                ),

                // Biometric shortcut
                if (_biometricAvailable) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _tryBiometric,
                    icon: const Icon(Icons.fingerprint_rounded),
                    label: const Text('Use biometric'),
                    style: TextButton.styleFrom(
                      foregroundColor: cs.onSurfaceVariant,
                    ),
                  ),
                ],

                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
