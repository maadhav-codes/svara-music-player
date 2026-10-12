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
      version: 2,
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) await _removeAudius(db);
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
  final _cache = <String, (DateTime, String)>{};
  int get cacheEntries => _cache.length;
  void clearSessionCache() => _cache.clear();
  Future<dynamic> cached(String key) async {
    final entry = _cache[key];
    if (entry == null) return null;
    if (!entry.$1.isAfter(DateTime.now())) {
      _cache.remove(key);
      return null;
    }
    return jsonDecode(entry.$2);
  }

  Future<void> cache(
    String key,
    dynamic value, {
    Duration ttl = const Duration(hours: 6),
  }) async {
    final data = jsonEncode(value);
    if (data.length > 500000) return;
    _cache.removeWhere((key, entry) => !entry.$1.isAfter(DateTime.now()));
    _cache.remove(key);
    while (_cache.length >= 20) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = (DateTime.now().add(ttl), data);
  }
}
