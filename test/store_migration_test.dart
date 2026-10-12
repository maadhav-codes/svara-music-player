import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/store.dart';
import 'package:svara/core/track.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  for (final selected in [0, 1, 2]) {
    test('v1 migration preserves supported collections; selected=$selected', () async {
      final directory = await Directory.systemTemp.createTemp(
        'svara-migration-',
      );
      final path = '${directory.path}/svara.db';
      final legacy = await openDatabase(
        path,
        version: 1,
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
      const local = Track(
        id: 'local:1',
        title: 'Local',
        artist: 'A',
        uri: 'content://media/1',
      );
      const youtube = Track(
        id: 'youtube:aaaaaaaaaaa',
        title: 'Song',
        artist: 'Channel',
        uri: 'https://www.youtube.com/watch?v=aaaaaaaaaaa',
      );
      final retired = {
        'id': 'audius:old',
        'source': 'audius',
        'title': 'Old',
        'artist': 'Old',
        'uri': 'https://api.audius.co/v1/tracks/old/stream',
      };
      final tracks = [retired, local.toSavedJson(), youtube.toSavedJson()];
      final oldStore = Store(legacy);
      await oldStore.write('favorites', ['audius:old', local.id, youtube.id]);
      await oldStore.write('favoriteTracks', tracks);
      await oldStore.write('playlists', [
        {'id': 'mixed', 'name': 'Evening', 'tracks': tracks},
        {
          'id': 'retired',
          'name': 'Old list',
          'tracks': [retired],
        },
      ]);
      await oldStore.write('playback', {
        'tracks': tracks,
        'index': selected,
        'position': 9000,
        'repeat': 'all',
        'shuffle': true,
      });
      await oldStore.write('youtubeEnabled', false);
      await oldStore.write('streamQuality', 'high');
      await oldStore.write('theme', 'dark');
      for (final track in tracks) {
        await legacy.insert('tracks', {
          'id': track['id'],
          'data': jsonEncode(track),
        });
        await legacy.insert('history', {'id': track['id'], 'played': 123});
      }
      await legacy.close();
      final store = await Store.open(path: path);
      try {
        expect(await store.db.getVersion(), 2);
        expect(await store.read('favorites'), [local.id, youtube.id]);
        expect(await store.read('favoriteTracks'), tracks.sublist(1));
        final playlists = await store.read('playlists') as List;
        expect(playlists[0]['name'], 'Evening');
        expect(playlists[0]['tracks'], tracks.sublist(1));
        expect(playlists[1]['name'], 'Old list');
        expect(playlists[1]['tracks'], isEmpty);
        final playback = await store.read('playback') as Map;
        expect(playback['tracks'], tracks.sublist(1));
        expect(playback['index'], selected == 2 ? 1 : 0);
        expect(playback['position'], selected == 0 ? 0 : 9000);
        expect(playback['repeat'], 'all');
        expect(playback['shuffle'], true);
        expect(await store.read('youtubeEnabled'), isNull);
        expect(await store.read('streamQuality'), 'high');
        expect(await store.read('theme'), 'dark');
        expect((await store.tracks()).map((track) => track.id).toSet(), {
          local.id,
          youtube.id,
        });
        expect((await store.history()).keys.toSet(), {local.id, youtube.id});
      } finally {
        await store.db.close();
        await directory.delete(recursive: true);
      }
    });
  }
}
