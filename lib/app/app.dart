import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'router.dart';
import 'themes/app_theme.dart';
import '../features/lock/lock_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/onboarding/welcome_screen.dart';
import '../state/prefs_providers.dart';

class SpendWiseApp extends StatelessWidget {
  const SpendWiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const _AppContent();
  }
}

class _AppContent extends ConsumerStatefulWidget {
  const _AppContent();

  @override
  ConsumerState<_AppContent> createState() => _AppContentState();
}

class _AppContentState extends ConsumerState<_AppContent>
    with WidgetsBindingObserver {
  bool _showWelcome = false;
  bool _showOnboarding = false;
  bool _showLock = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final prefs = ref.read(prefsServiceProvider);
    _showWelcome = prefs.isFirstRun;
    _showOnboarding = false;
    if (!_showWelcome && prefs.lockEnabled) _showLock = true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // paused = Android backgrounded; hidden = iOS before paused when switching apps
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (!mounted) return;
      if (!ref.read(lockEnabledProvider)) return;
      final bg = _backgroundedAt;
      if (bg == null) return;
      final elapsed = DateTime.now().difference(bg).inSeconds;
      final timeout = ref.read(prefsServiceProvider).lockTimeoutSeconds;
      if (elapsed >= timeout) setState(() => _showLock = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final oledDark = ref.watch(oledDarkProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'SpendWise',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(oled: oledDark),
      themeMode: themeMode,
      routerConfig: AppRouter.config,
      builder: (context, child) {
        if (_showWelcome) {
          return WelcomeScreen(
            onGetStarted: () => setState(() {
              _showWelcome = false;
              _showOnboarding = true;
            }),
          );
        }
        if (_showOnboarding) {
          return OnboardingScreen(
            onDone: () {
              ref.read(prefsServiceProvider).completeFirstRun();
              setState(() {
                _showOnboarding = false;
                if (ref.read(lockEnabledProvider)) _showLock = true;
              });
            },
          );
        }
        if (_showLock) {
          return LockScreen(onUnlocked: () => setState(() => _showLock = false));
        }
        return child!;
      },
    );
  }
}
