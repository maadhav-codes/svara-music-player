import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/store.dart';
import '../../core/track.dart';

class Playlist {
  static const favoritesId = 'favorites';
  const Playlist(this.id, this.name, this.tracks);
  final String id, name;
  final List<Track> tracks;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'tracks': tracks.map((t) => t.toSavedJson()).toList(),
  };
  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
    j['id'] as String,
    j['name'] as String,
    (j['tracks'] as List)
        .map((t) => Track.fromJson(Map<String, dynamic>.from(t as Map)))
        .toList(),
  );
}

class PlaylistsRepository {
  PlaylistsRepository(this.store);
  final Store store;
  Future<List<Playlist>> _read(DatabaseExecutor db) async {
    final rows = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['playlists'],
    );
    return rows.isEmpty
        ? []
        : (jsonDecode(rows.single['value'] as String) as List)
              .map(
                (j) => Playlist.fromJson(Map<String, dynamic>.from(j as Map)),
              )
              .toList();
  }

  Future<void> _write(DatabaseExecutor db, List<Playlist> playlists) async {
    await db.insert('settings', {
      'key': 'playlists',
      'value': jsonEncode(playlists.map((p) => p.toJson()).toList()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Playlist>> all() async =>
      (await _read(store.db))
          .where((p) => p.id != Playlist.favoritesId)
          .toList();

  Future<Playlist> favorites() async =>
      (await _read(store.db))
          .where((p) => p.id == Playlist.favoritesId)
          .firstOrNull ??
      const Playlist(Playlist.favoritesId, 'Favorites', []);

  // User playlist edits cannot rename, delete, or overwrite the pinned list.
  Future<void> save(List<Playlist> playlists) =>
      store.db.transaction((tx) async {
        final pinned = (await _read(tx))
            .where((p) => p.id == Playlist.favoritesId);
        await _write(tx, [
          ...pinned,
          ...playlists.where((p) => p.id != Playlist.favoritesId),
        ]);
      });

  Future<Set<String>> toggleFavorite(Track track) =>
      store.db.transaction((tx) async {
        final playlists = await _read(tx);
        final current = playlists
            .where((p) => p.id == Playlist.favoritesId)
            .firstOrNull;
        final tracks = List<Track>.of(current?.tracks ?? []);
        if (tracks.any((t) => t.id == track.id)) {
          tracks.removeWhere((t) => t.id == track.id);
        } else {
          tracks.insert(0, track);
        }
        await _write(tx, [
          Playlist(Playlist.favoritesId, 'Favorites', tracks),
          ...playlists.where((p) => p.id != Playlist.favoritesId),
        ]);
        return tracks.map((t) => t.id).toSet();
      });
}
