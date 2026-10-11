import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import 'store.dart';
import '../features/library/library_repository.dart';
import '../features/discovery/audius_repository.dart';
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
  @override
  Set<String> build() => {};
  Future<void> load() async {
    state = ((await ref.read(storeProvider).read('favorites') as List?) ?? [])
        .cast<String>()
        .toSet();
  }

  Future<void> toggle(String id) async {
    final next = {...state};
    if (!next.add(id)) next.remove(id);
    state = next;
    await ref.read(storeProvider).write('favorites', state.toList());
  }
}
