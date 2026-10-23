import 'package:flutter/material.dart';

import '../services/session.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Five tabs; Explore is the default. The Profile tab opens the Plans screen.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  static final tabIndex = ValueNotifier<int>(2);
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  final _built = <int>{2};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) session.refresh().catchError((_) {});
  }

  Widget _tab(int i) => switch (i) {
        0 => const _Placeholder('Cloud', Icons.cloud_outlined),
        1 => const _Placeholder('Feed', Icons.dynamic_feed_outlined),
        2 => const _Placeholder('Explore', Icons.explore_outlined),
        3 => const _Placeholder('Channels', Icons.video_library_outlined),
        _ => const _Placeholder('Plans', Icons.workspace_premium_outlined),
      };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: HomeShell.tabIndex,
      builder: (context, index, _) {
        _built.add(index);
        return Scaffold(
          body: IndexedStack(
            index: index,
            children: [for (var i = 0; i < 5; i++) _built.contains(i) ? _tab(i) : const SizedBox.shrink()],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => HomeShell.tabIndex.value = i,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.cloud_outlined), selectedIcon: Icon(Icons.cloud), label: 'Cloud'),
              NavigationDestination(
                  icon: Icon(Icons.dynamic_feed_outlined), selectedIcon: Icon(Icons.dynamic_feed), label: 'Feed'),
              NavigationDestination(
                  icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Explore'),
              NavigationDestination(
                  icon: Icon(Icons.video_library_outlined),
                  selectedIcon: Icon(Icons.video_library),
                  label: 'Channels'),
              NavigationDestination(
                  icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
            ],
          ),
        );
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.title, this.icon);
  final String title;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: EmptyState(text: '$title is coming in the next stage.', icon: icon),
        backgroundColor: AppColors.background,
      );
}
