import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import 'track.dart';

class Store {
  Store(this.db);
  final Database db;
  static Future<Store> open({String? path}) async {
    final db = await openDatabase(
      path ?? p.join(await getDatabasesPath(), 'svara.db'),
      version: 3,
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) await _removeAudius(db);
        if (oldVersion < 3) await _migrateFavorites(db);
      },
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE tracks (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE history (id TEXT PRIMARY KEY, played INTEGER NOT NULL)',
        );
      },
    );
    return Store(db);
  }

  // Version 2 retires Audius without changing local/YouTube references or lists.
  static Future<void> _removeAudius(DatabaseExecutor db) async {
    bool retired(dynamic value) => value is Map
        ? value['source'] == 'audius' || retired(value['id'])
        : value is String && value.startsWith('audius:');
    List<dynamic> keep(List<dynamic> values) =>
        values.where((value) => !retired(value)).toList();
    for (final row in await db.query('settings')) {
      final key = row['key'] as String;
      dynamic value = jsonDecode(row['value'] as String);
      switch (key) {
        case 'favorites':
        case 'favoriteTracks':
          value = keep(value as List);
        case 'playlists':
          value = [
            for (final playlist in value as List)
              {...playlist as Map, 'tracks': keep(playlist['tracks'] as List)},
          ];
        case 'playback':
          final original = value['tracks'] as List;
          final selected = (value['index'] as int? ?? 0).clamp(
            0,
            original.isEmpty ? 0 : original.length - 1,
          );
          final tracks = keep(original);
          final index = keep(original.take(selected).toList()).length
              .clamp(0, tracks.isEmpty ? 0 : tracks.length - 1);
          value = {
            ...value as Map,
            'tracks': tracks,
            'index': index,
            if (original.isEmpty || retired(original[selected])) 'position': 0,
          };
        default:
          continue;
      }
      await db.update(
        'settings',
        {'value': jsonEncode(value)},
        where: 'key = ?',
        whereArgs: [key],
      );
    }
    await db.delete(
      'settings',
      where: 'key = ?',
      whereArgs: ['youtubeEnabled'],
    );
    await db.delete('history', where: 'id LIKE ?', whereArgs: ['audius:%']);
    for (final row in await db.query('tracks')) {
      if (retired(row['id']) || retired(jsonDecode(row['data'] as String))) {
        await db.delete('tracks', where: 'id = ?', whereArgs: [row['id']]);
      }
    }
  }

  // Upgrade legacy ID-only favorites once. Normal reads use the pinned playlist.
  static Future<void> _migrateFavorites(DatabaseExecutor db) async {
    final settings = {
      for (final row in await db.query('settings'))
        row['key'] as String: jsonDecode(row['value'] as String),
    };
    final known = <String, Track>{};
    void collect(List? values) {
      for (final value in values ?? []) {
        final track = Track.fromJson(Map<String, dynamic>.from(value as Map));
        known[track.id] = track;
      }
    }

    final playback = settings['playback'] as Map?;
    collect(playback?['tracks'] as List?);
    final playlists = (settings['playlists'] as List? ?? []).cast<Map>();
    for (final playlist in playlists) {
      collect(playlist['tracks'] as List?);
    }
    final saved = settings['favoriteTracks'] as List? ?? [];
    collect(saved);
    for (final row in await db.query('tracks')) {
      final track = Track.fromJson(jsonDecode(row['data'] as String));
      known[track.id] = track;
      await db.update(
        'tracks',
        {'data': jsonEncode(track.toJson())},
        where: 'id = ?',
        whereArgs: [track.id],
      );
    }
    final ids =
        (settings['favorites'] as List? ?? saved.map((t) => t['id']).toList())
            .cast<String>()
            .toSet();
    final order = <String>{for (final t in saved) t['id'] as String, ...ids};
    final favorites = [
      for (final id in order)
        if (ids.contains(id))
          (known[id] ??
                  Track(
                    id: id,
                    title: id.startsWith('youtube:')
                        ? 'YouTube track'
                        : 'Unavailable local track',
                    artist: id.startsWith('youtube:')
                        ? 'YouTube'
                        : 'Unknown artist',
                    uri: '',
                    streamable: id.startsWith('youtube:'),
                  ))
              .toSavedJson(),
    ];
    final normalized = [
      if (!playlists.any((p) => p['id'] == 'favorites'))
        {'id': 'favorites', 'name': 'Favorites', 'tracks': favorites},
      for (final playlist in playlists)
        {
          ...playlist,
          'tracks': [
            for (final t in playlist['tracks'] as List)
              Track.fromJson(Map<String, dynamic>.from(t as Map)).toSavedJson(),
          ],
        },
    ];
    await db.insert('settings', {
      'key': 'playlists',
      'value': jsonEncode(normalized),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    if (playback != null) {
      await db.update(
        'settings',
        {
          'value': jsonEncode({
            ...playback,
            'tracks': [
              for (final t in playback['tracks'] as List)
                Track.fromJson(Map<String, dynamic>.from(t as Map))
                    .toSavedJson(),
            ],
          }),
        },
        where: 'key = ?',
        whereArgs: ['playback'],
      );
    }
    await db.delete(
      'settings',
      where: 'key IN (?, ?)',
      whereArgs: ['favorites', 'favoriteTracks'],
    );
  }

  Future<dynamic> read(String key) async {
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : jsonDecode(rows.first['value'] as String);
  }

  Future<void> write(String key, Object? value) => db.insert('settings', {
    'key': key,
    'value': jsonEncode(value),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<List<Track>> tracks({int offset = 0, int limit = 200}) async =>
      (await db.query(
        'tracks',
        limit: limit,
        offset: offset,
        orderBy: 'id',
      )).map((r) => Track.fromJson(jsonDecode(r['data'] as String))).toList();
  Future<void> reconcile(List<Track> changed, Set<String> ids) async {
    await db.transaction((tx) async {
      final batch = tx.batch();
      for (final t in changed) {
        batch.insert('tracks', {
          'id': t.id,
          'data': jsonEncode(t.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final row in await tx.query('tracks', columns: ['id'])) {
        if (!ids.contains(row['id'])) {
          batch.delete('tracks', where: 'id = ?', whereArgs: [row['id']]);
        }
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> played(String id) async {
    await db.insert('history', {
      'id': id,
      'played': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.execute(
      'DELETE FROM history WHERE id NOT IN (SELECT id FROM history ORDER BY played DESC LIMIT 1000)',
    );
  }

  Future<Map<String, int>> history() async => {
    for (final r in await db.query('history'))
      r['id'] as String: r['played'] as int,
  };
}
