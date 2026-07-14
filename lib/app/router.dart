import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/ai/presentation/ai_chat_list_screen.dart';
import '../features/ai/presentation/ai_chat_screen.dart';
import '../features/ai/presentation/ai_report_screen.dart';
import '../features/ai/presentation/ai_settings_screen.dart';
import '../features/bills/bills_screen.dart';
import '../features/digest/digest_preview_screen.dart';
import '../features/dues/dues_screen.dart';
import '../features/dues/contact_detail_screen.dart';
import '../features/goals/goals_screen.dart';
import '../features/home/home_screen.dart';
import '../features/manage/manage_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/reports/custom/custom_report_builder_screen.dart';
import '../features/reports/custom/custom_report_view_screen.dart';
import '../features/settings/settings_screen.dart';
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
              path: '/dues',
              builder: (context, state) => const DuesScreen(),
              routes: [
                GoRoute(
                  path: ':contactId',
                  builder: (context, state) => ContactDetailScreen(
                    contactId: state.pathParameters['contactId']!,
                  ),
                ),
              ],
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
      // An explicit unique `name` forces a distinct Navigator page key for
      // these top-level (root-navigator) routes. go_router derives page keys
      // from the route when `name` is absent, and pushing a root-navigator
      // route from inside a StatefulShellRoute.indexedStack branch can in some
      // 14.x releases collide and trip `_debugCheckDuplicatedPageKeys`. Unique
      // names eliminate that collision class.
      GoRoute(
        name: 'manage',
        parentNavigatorKey: _rootNavigatorKey,
        path: '/manage',
        builder: (context, state) => const ManageScreen(),
      ),
      // Bills & subscriptions — pushed top-level (not a tab). Plain builder
      // (no slide pageBuilder) keeps it consistent with /manage.
      GoRoute(
        name: 'bills',
        parentNavigatorKey: _rootNavigatorKey,
        path: '/bills',
        builder: (context, state) => const BillsScreen(),
      ),
      // Goals & savings targets — pushed top-level (not a tab).
      GoRoute(
        name: 'goals',
        parentNavigatorKey: _rootNavigatorKey,
        path: '/goals',
        builder: (context, state) => const GoalsScreen(),
      ),
      // Weekly digest preview — pushed top-level (not a tab).
      GoRoute(
        name: 'digest',
        parentNavigatorKey: _rootNavigatorKey,
        path: '/digest',
        builder: (context, state) => const DigestPreviewScreen(),
      ),
      // Custom Report builder — pushed top-level (not a tab). The optional
      // `?id=...` query param opens the builder prefilled for that saved report
      // (used by the view screen's Edit action and the hub's saved-report rows).
      GoRoute(
        name: 'custom-report-builder',
        parentNavigatorKey: _rootNavigatorKey,
        path: '/reports/custom-builder',
        builder: (context, state) => CustomReportBuilderScreen(
          existingId: state.uri.queryParameters['id'],
        ),
      ),
      // Saved Custom Report view — pushed top-level (not a tab).
      GoRoute(
        name: 'custom-report-view',
        parentNavigatorKey: _rootNavigatorKey,
        path: '/reports/custom/:id',
        builder: (context, state) => CustomReportViewScreen(
          id: state.pathParameters['id']!,
        ),
      ),
      // AI Copilot screens are pushed top-level (not in a tab) so the 5-tab
      // shell stays untouched. They use an explicit slide-in `pageBuilder`
      // (rather than the default `builder`) because the chat ↔ chats-list ↔
      // chat flow navigates with `replace`, which otherwise swaps pages with a
      // jarring jump/flash. A consistent slide makes every swap feel like a
      // smooth forward push (and pops slide back out the same way).
      GoRoute(
        name: 'ai-chats',
        parentNavigatorKey: _rootNavigatorKey,
        path: '/ai/chats',
        pageBuilder: (context, state) => _aiPage(state, const AiChatListScreen()),
      ),
      GoRoute(
        name: 'ai-ask',
        parentNavigatorKey: _rootNavigatorKey,
        path: '/ai/ask/:threadId',
        pageBuilder: (context, state) => _aiPage(
          state,
          AiChatScreen(threadId: state.pathParameters['threadId']!),
        ),
      ),
      GoRoute(
        name: 'ai-settings',
        parentNavigatorKey: _rootNavigatorKey,
        path: '/ai/settings',
        pageBuilder: (context, state) => _aiPage(state, const AiSettingsScreen()),
      ),
      GoRoute(
        name: 'ai-report',
        parentNavigatorKey: _rootNavigatorKey,
        path: '/ai/report',
        pageBuilder: (context, state) => _aiPage(state, const AiReportScreen()),
      ),
    ],
  );
}

/// Smooth slide-in [Page] for the AI Copilot routes.
///
/// Used by `/ai/chats`, `/ai/ask/:threadId`, and `/ai/settings`. The chat and
/// chats-list screens navigate between each other with `context.replace`
/// (to keep the back stack one screen deep), and a bare `replace` swaps pages
/// with an abrupt jump. This gives every swap a consistent, eased slide-in from
/// the right (and the matching slide-out on pop), so transitions feel like a
/// normal forward navigation regardless of push-vs-replace.
CustomTransitionPage<void> _aiPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curve),
        child: FadeTransition(opacity: curve, child: child),
      );
    },
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
    icon: Icons.book_outlined,
    activeIcon: Icons.book_rounded,
    label: 'Dues',
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
      ),
    );
  }
}

// ── Mono bottom bar ────────────────────────────────────────────────────────────

class _MonoBottomBar extends StatelessWidget {
  const _MonoBottomBar({
    required this.selectedIndex,
    required this.onTabTap,
  });

  final int selectedIndex;
  final ValueChanged<int> onTabTap;

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
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(dest: _destinations[0], active: selectedIndex == 0, onTap: () => onTabTap(0)),
              _NavItem(dest: _destinations[1], active: selectedIndex == 1, onTap: () => onTabTap(1)),
              _NavItem(dest: _destinations[2], active: selectedIndex == 2, onTap: () => onTabTap(2)),
              _NavItem(dest: _destinations[3], active: selectedIndex == 3, onTap: () => onTabTap(3)),
              _NavItem(dest: _destinations[4], active: selectedIndex == 4, onTap: () => onTabTap(4)),
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

