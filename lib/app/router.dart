import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/home/home_screen.dart';
import '../features/manage/manage_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/transactions/sheets/amount_entry_sheet.dart';
import '../features/transactions/transactions_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

class AppRouter {
  static final GoRouter config = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/home',
    debugLogDiagnostics: false,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            _AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/transactions',
              builder: (context, state) => const TransactionsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/reports',
              builder: (context, state) => const ReportsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreenV2(),
            ),
          ]),
        ],
      ),
      // Manage is pushed from Settings, not a bottom-tab branch.
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/manage',
        builder: (context, state) => const ManageScreen(),
      ),
    ],
  );
}

// ── Destination model ──────────────────────────────────────────────────────────

class _Dest {
  const _Dest({required this.icon, required this.activeIcon, required this.label});
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

const _destinations = [
  _Dest(
    icon: Icons.home_outlined,
    activeIcon: Icons.home_rounded,
    label: 'Home',
  ),
  _Dest(
    icon: Icons.receipt_long_outlined,
    activeIcon: Icons.receipt_long_rounded,
    label: 'Transactions',
  ),
  _Dest(
    icon: Icons.bar_chart_outlined,
    activeIcon: Icons.bar_chart_rounded,
    label: 'Reports',
  ),
  _Dest(
    icon: Icons.settings_outlined,
    activeIcon: Icons.settings_rounded,
    label: 'Settings',
  ),
];

// ── App shell ─────────────────────────────────────────────────────────────────

class _AppShell extends StatelessWidget {
  const _AppShell({required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: _MonoBottomBar(
        selectedIndex: navigationShell.currentIndex,
        onTabTap: (i) => navigationShell.goBranch(
          i,
          initialLocation: i == navigationShell.currentIndex,
        ),
        onAddTap: () => showAmountEntrySheet(context),
      ),
    );
  }
}

// ── Mono bottom bar ────────────────────────────────────────────────────────────

class _MonoBottomBar extends StatelessWidget {
  const _MonoBottomBar({
    required this.selectedIndex,
    required this.onTabTap,
    required this.onAddTap,
  });

  final int selectedIndex;
  final ValueChanged<int> onTabTap;
  final VoidCallback onAddTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outline, width: 0.8)),
      ),
      child: SizedBox(
        height: 60 + bottom,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Row(
            children: [
              // Left two tabs
              _NavItem(dest: _destinations[0], active: selectedIndex == 0,
                  onTap: () => onTabTap(0)),
              _NavItem(dest: _destinations[1], active: selectedIndex == 1,
                  onTap: () => onTabTap(1)),
              // Centre + button
              _CenterAddButton(onTap: onAddTap),
              // Right two tabs
              _NavItem(dest: _destinations[2], active: selectedIndex == 2,
                  onTap: () => onTabTap(2)),
              _NavItem(dest: _destinations[3], active: selectedIndex == 3,
                  onTap: () => onTabTap(3)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.dest,
    required this.active,
    required this.onTap,
  });
  final _Dest dest;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = active ? cs.primary : cs.onSurfaceVariant;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              active ? dest.activeIcon : dest.icon,
              size: 24,
              color: color,
            ),
            const SizedBox(height: 3),
            Text(
              dest.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterAddButton extends StatelessWidget {
  const _CenterAddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 72,
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: cs.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.add_rounded, color: cs.onPrimary, size: 28),
          ),
        ),
      ),
    );
  }
}
