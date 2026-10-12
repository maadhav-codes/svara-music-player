import 'dart:convert';

import '../../core/store.dart';
import '../../core/track.dart';

/// Keeps the existing favorite IDs and playable references in sync.
class FavoritesRepository {
  FavoritesRepository(this.store);
  final Store store;

  Future<Set<String>> ids() async =>
      ((await store.read('favorites') as List?) ?? []).cast<String>().toSet();

  Future<Set<String>> toggle(Track track) async {
    final next = await ids();
    final saved = ((await store.read('favoriteTracks') as List?) ?? [])
        .cast<Map>()
        .map((j) => Map<String, dynamic>.from(j))
        .where((j) => j['id'] != track.id)
        .toList();
    if (next.remove(track.id) == false) {
      next.add(track.id);
      saved.insert(0, track.toSavedJson());
    }
    await store.db.transaction((tx) async {
      for (final entry in {
        'favorites': next.toList(),
        'favoriteTracks': saved,
      }.entries) {
        await tx.rawInsert(
          'INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)',
          [entry.key, jsonEncode(entry.value)],
        );
      }
    });
    return next;
  }

  Future<List<Track>> tracks() async {
    final selected = await ids();
    final known = <String, Track>{};
    void collect(List? values) {
      for (final value in values ?? []) {
        final track = Track.fromJson(Map<String, dynamic>.from(value as Map));
        known[track.id] = track;
      }
    }

    // Recover old ID-only favorites from saved queues and playlists where possible.
    final playback = await store.read('playback') as Map?;
    collect(playback?['tracks'] as List?);
    for (final playlist in (await store.read('playlists') as List?) ?? []) {
      collect((playlist as Map)['tracks'] as List?);
    }
    final saved = await store.read('favoriteTracks') as List?;
    collect(saved);
    for (var offset = 0; ; offset += 200) {
      final page = await store.tracks(offset: offset);
      for (final track in page) {
        known[track.id] = track;
      }
      if (page.length < 200) break;
    }
    // Online IDs remain resolvable even if their old display metadata was lost.
    for (final id in selected) {
      if (known.containsKey(id)) continue;
      if (id.startsWith('youtube:')) {
        known[id] = Track(
          id: id,
          title: 'YouTube track',
          artist: 'YouTube',
          uri: '',
        );
      }
    }
    final order = <String>{
      for (final value in saved ?? []) (value as Map)['id'] as String,
      ...selected,
    };
    return [
      for (final id in order)
        if (selected.contains(id) && known.containsKey(id)) known[id]!,
    ];
  }
}
