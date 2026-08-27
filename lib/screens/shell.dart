import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'buddies_screen.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'watchlist_screen.dart';

/// The signed-in frame: five destinations behind a single persistent bar.
///
/// Each tab keeps its own navigation stack, so opening a title from Watchlist and
/// pressing back returns to Watchlist rather than dumping the viewer on Home.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _destinations = <_Destination>[
    _Destination('Home', Icons.home_outlined, Icons.home_rounded),
    _Destination('Watchlist', Icons.bookmark_outline_rounded, Icons.bookmark_rounded),
    _Destination('History', Icons.history_rounded, Icons.history_rounded),
    _Destination('Buddies', Icons.people_outline_rounded, Icons.people_rounded),
    _Destination('Profile', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  int _index = 0;
  final _navigatorKeys = List.generate(5, (_) => GlobalKey<NavigatorState>());

  /// Back pops the active tab's own stack first, then falls back to Home, and
  /// only then leaves the app.
  bool _handleBack() {
    final navigator = _navigatorKeys[_index].currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return false;
    }
    if (_index != 0) {
      setState(() => _index = 0);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_handleBack()) SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < _destinations.length; i++)
              Navigator(
                key: _navigatorKeys[i],
                onGenerateRoute: (settings) => MaterialPageRoute(
                  settings: settings,
                  builder: (_) => _pageFor(i),
                ),
              ),
          ],
        ),
        bottomNavigationBar: _BottomBar(
          index: _index,
          destinations: _destinations,
          onSelected: (next) {
            // Tapping the active tab pops it back to its root.
            if (next == _index) {
              _navigatorKeys[next].currentState?.popUntil((route) => route.isFirst);
              return;
            }
            setState(() => _index = next);
          },
        ),
      ),
    );
  }

  Widget _pageFor(int index) => switch (index) {
        1 => const WatchlistScreen(),
        2 => const HistoryScreen(),
        3 => const BuddiesScreen(),
        4 => const ProfileScreen(),
        _ => const HomeScreen(),
      };
}

class _Destination {
  const _Destination(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.index,
    required this.destinations,
    required this.onSelected,
  });

  final int index;
  final List<_Destination> destinations;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.bgSoft,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: _BarItem(
                    destination: destinations[i],
                    selected: i == index,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.textSecondary;

    return InkResponse(
      onTap: onTap,
      radius: 42,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // A short gold rule above the active icon, echoing the site's tab indicator.
          AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.curve,
            height: 2,
            width: selected ? 18 : 0,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: AppRadius.all(AppRadius.pill),
            ),
          ),
          const SizedBox(height: 6),
          Icon(selected ? destination.activeIcon : destination.icon, size: 23, color: color),
          const SizedBox(height: 3),
          Text(
            destination.label,
            style: AppText.caption.copyWith(
              color: color,
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
