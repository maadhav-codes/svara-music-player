import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import 'store.dart';
import 'track.dart';
import '../features/playlists/favorites_repository.dart';
import '../features/library/library_repository.dart';
import '../features/discovery/audius_repository.dart';
import '../features/discovery/youtube_repository.dart';
import '../features/player/svara_handler.dart';

final storeProvider = Provider<Store>((ref) => throw UnimplementedError());
final handlerProvider = Provider<SvaraHandler>(
  (ref) => throw UnimplementedError(),
);
final libraryRepositoryProvider = Provider(
  (ref) => LibraryRepository(ref.watch(storeProvider)),
);
final audiusProvider = Provider(
  (ref) => AudiusRepository(ref.watch(storeProvider)),
);
final youtubeProvider = Provider(
  (ref) => YouTubeRepository(ref.watch(storeProvider)),
);
final themeProvider = NotifierProvider<ThemeController, ThemeMode>(
  ThemeController.new,
);

class ThemeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;
  Future<void> load() async {
    final name = await ref.read(storeProvider).read('theme');
    state = ThemeMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(storeProvider).write('theme', mode.name);
  }
}

final favoritesProvider = NotifierProvider<FavoritesController, Set<String>>(
  FavoritesController.new,
);

class FavoritesController extends Notifier<Set<String>> {
  Future<void> _pending = Future<void>.value();

  Future<void> _serialize(Future<void> Function() action) {
    final operation = _pending.then((_) => action());
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  @override
  Set<String> build() => {};
  Future<void> load() => _serialize(() async {
    state = await FavoritesRepository(ref.read(storeProvider)).ids();
  });

  Future<void> toggle(Track track) => _serialize(() async {
    state = await FavoritesRepository(ref.read(storeProvider)).toggle(track);
  });
}

final favoriteTracksProvider = FutureProvider<List<Track>>((ref) {
  ref.watch(favoritesProvider);
  return FavoritesRepository(ref.watch(storeProvider)).tracks();
});
