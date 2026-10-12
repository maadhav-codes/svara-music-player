import 'core/app_routes.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/theme.dart';
import 'features/library/library_screen.dart';
import 'features/discovery/discovery_screen.dart';
import 'features/playlists/playlists_screen.dart';
import 'features/player/player_screen.dart';
import 'features/settings/settings_screen.dart';

class SvaraApp extends ConsumerWidget {
  const SvaraApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    title: 'Svara',
    debugShowCheckedModeBanner: false,
    themeMode: ref.watch(themeProvider),
    theme: SvaraTheme.build(Brightness.light),
    darkTheme: SvaraTheme.build(Brightness.dark),
    home: const Home(),
  );
}

class Home extends ConsumerStatefulWidget {
  const Home({super.key});
  @override
  ConsumerState<Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<Home> {
  int index = 0;
  StreamSubscription<String>? errors;
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(themeProvider.notifier).load());
    unawaited(ref.read(favoritesProvider.notifier).load());
    errors = ref.read(handlerProvider).errors.stream.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Library',
            onPressed: () => setState(() => index = 0),
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    errors?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Row(
        children: [
          Icon(Icons.graphic_eq_rounded),
          SizedBox(width: 12),
          Text(
            'svara',
            style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 2),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Settings',
          icon: const Icon(Icons.tune_rounded),
          onPressed: () => Navigator.push(
            context,
            AppPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
        ),
      ],
    ),
    body: IndexedStack(
      index: index,
      children: [
        LibraryScreen(onDiscover: () => setState(() => index = 1)),
        const DiscoveryScreen(),
        PlaylistsScreen(onLibrary: () => setState(() => index = 0)),
      ],
    ),
    bottomNavigationBar: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const MiniPlayer(),
        NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (value) => setState(() => index = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.library_music_outlined),
              selectedIcon: Icon(Icons.library_music),
              label: 'Library',
            ),
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore),
              label: 'Discover',
            ),
            NavigationDestination(
              icon: Icon(Icons.queue_music),
              label: 'Playlists',
            ),
          ],
        ),
      ],
    ),
  );
}
