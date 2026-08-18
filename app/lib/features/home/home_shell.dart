import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../collection/collection_screen.dart';
import '../search/search_screen.dart';

/// The signed-in app shell: bottom-tab navigation between browsing the
/// catalog and the owned collection.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _tabs = [SearchScreen(), CollectionScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.search), label: 'Cards'),
          NavigationDestination(icon: Icon(Icons.style), label: 'Collection'),
        ],
      ),
    );
  }
}
