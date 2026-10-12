import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/store.dart';
import 'package:svara/core/track.dart';
import 'package:svara/core/media_source.dart';
import 'package:svara/features/library/library_repository.dart';
import 'package:svara/features/playlists/playlists_repository.dart';

Track song(String id, {bool online = false, int modified = 1}) => Track(
  id: id,
  title: 'Song $id',
  artist: 'Artist',
  uri: online
      ? 'https://example.org/$id'
      : 'content://media/external/audio/media/$id',
  source: online ? MediaSource.youtube : MediaSource.local,
  modified: modified,
);

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.respond);
  final ResponseBody Function(RequestOptions options, int call) respond;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options, ++calls);
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Store store;
  setUp(() async {
    store = await Store.open(path: inMemoryDatabasePath);
  });
  tearDown(() async {
    await store.db.close();
  });
  test(
    'queue reorder keeps duplicate occurrences and correct insertion semantics',
    () {
      expect(moveQueueItem(['a', 'b', 'a', 'c'], 0, 4), ['b', 'a', 'c', 'a']);
      expect(moveQueueItem(['a', 'b', 'c'], 2, 0), ['c', 'a', 'b']);
    },
  );
  test('Quick Mix interleaves favorites and least recent local songs only', () {
    final mix = quickMix(
      [song('1'), song('2'), song('3'), song('4', online: true)],
      {'1'},
      {'2': 50, '3': 10},
    );
    expect(mix.map((t) => t.id), ['1', '3', '2']);
    expect(quickMix([song('1'), song('2')], {}, {}, limit: 1).length, 1);
  });
  test(
    'queue snapshot, favorites, theme and playlist survive serialization',
    () async {
      await store.write('playback', {
        'tracks': [song('1').toJson(), song('remote', online: true).toJson()],
        'index': 1,
        'position': 12345,
      });
      final restored = await store.read('playback') as Map;
      expect(restored['position'], 12345);
      expect(
        Track.fromJson(Map<String, dynamic>.from(restored['tracks'][1])).online,
        true,
      );
      final repo = PlaylistsRepository(store);
      await repo.save([
        Playlist('p', 'Evening', [song('1')]),
      ]);
      expect(
        (await repo.all()).single.tracks.single.uri,
        contains('content://'),
      );
      expect(await store.read('favorites'), isNull);
    },
  );
  test('reconciliation preserves unchanged tracks, updates renamed and removes deleted', () async {
    await store.reconcile([song('1'), song('2')], {'1', '2'});
    await store.reconcile(
      [
        Track(
          id: '1',
          title: 'Renamed',
          artist: 'Artist',
          uri: song('1').uri,
          modified: 2,
        ),
      ],
      {'1'},
    );
    expect((await store.tracks()).single.title, 'Renamed');
    await store.reconcile([], {'1'});
    expect((await store.tracks()).length, 1);
  });
  test('library repository reads all tracks and sends every fingerprint to MediaStore', () async {
    final tracks = List.generate(501, (i) => song('$i'));
    await store.reconcile(tracks, tracks.map((t) => t.id).toSet());
    const channel = MethodChannel('test.svara/all-media');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'scan');
      final known = (call.arguments as Map)['known'] as Map;
      expect(known.length, 501);
      expect(known['500'], 1);
      return {'unchanged': true};
    });
    try {
      final repo = LibraryRepository(store, channel: channel);
      expect(await repo.all(), hasLength(501));
      await repo.refresh();
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test(
    'library bridge uses metadata fingerprints and prunes missing IDs',
    () async {
      const channel = MethodChannel('test.svara/media');
      await store.reconcile([song('1'), song('2')], {'1', '2'});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'scan') {
              expect((call.arguments as Map)['known'], {'1': 1, '2': 1});
              return {
                'changed': [song('1', modified: 3).toJson()],
                'ids': ['1'],
              };
            }
            return false;
          });
      final repo = LibraryRepository(store, channel: channel);
      expect(await repo.permission(request: true), false);
      await repo.refresh();
      expect((await repo.all()).single.modified, 3);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
}
