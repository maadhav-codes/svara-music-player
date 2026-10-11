import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
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
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: const Home(),
  );
  ThemeData _theme(Brightness brightness) => ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff21594b),
      brightness: brightness,
    ),
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xfff6f4ee)
        : const Color(0xff101714),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
    ),
    visualDensity: VisualDensity.standard,
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
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
        ),
      ],
    ),
    body: IndexedStack(
      index: index,
      children: [
        const LibraryScreen(),
        if (index == 1) const DiscoveryScreen() else const SizedBox(),
        if (index == 2) const PlaylistsScreen() else const SizedBox(),
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
