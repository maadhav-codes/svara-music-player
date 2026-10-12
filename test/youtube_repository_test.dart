import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/media_source.dart';
import 'package:svara/core/store.dart';
import 'package:svara/core/track.dart';
import 'package:svara/features/discovery/youtube_repository.dart';
import 'package:svara/features/playlists/playlists_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  const channel = MethodChannel('test.svara/youtube');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Store store;
  late YouTubeRepository repo;
  final dto = {
    'videoId': 'aaaaaaaaaaa',
    'title': 'Test recording',
    'uploader': 'Uploader',
    'durationMs': 30000,
  };
  const reference = Track(
    id: 'youtube:aaaaaaaaaaa',
    title: 'YouTube track',
    artist: 'YouTube',
    uri: 'https://www.youtube.com/watch?v=aaaaaaaaaaa',
  );
  setUp(() async {
    store = await Store.open(path: inMemoryDatabasePath);
    repo = YouTubeRepository(store, channel: channel, delay: (_) async {});
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await store.db.close();
  });

  test('search cache is repository-owned, bounded, and expires after fifteen minutes', () async {
    var now = DateTime(2026);
    repo = YouTubeRepository(store, channel: channel, now: () => now);
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return {
        'tracks': [dto],
        'continuation': null,
      };
    });
    await repo.search('song 0');
    await repo.search('song 0');
    expect(calls, 1);
    final other = YouTubeRepository(store, channel: channel);
    await other.search('song 0');
    expect(calls, 2);
    for (var i = 1; i <= 20; i++) {
      await repo.search('song $i');
    }
    expect(repo.cacheEntries, 20);
    await repo.search('song 0');
    expect(calls, 23); // First key was evicted.
    now = now.add(const Duration(minutes: 15));
    await repo.search('song 0');
    expect(calls, 24);
    expect(repo.cacheEntries, 1);
  });

  test(
    'paginated search preserves attribution and bounded session cache',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        expect(call.method, 'search');
        final args = call.arguments as Map;
        expect(args['query'], 'music');
        return {
          'tracks': [dto],
          'continuation': args['continuation'] == null ? 'opaque-page' : null,
        };
      });
      final first = await repo.search(' music ');
      expect(first.tracks.single.artist, 'Uploader');
      expect(first.tracks.single.source, MediaSource.youtube);
      expect(first.continuation, 'opaque-page');
      await repo.search('music');
      expect(calls, 1);
      final second = await repo.search(
        'music',
        continuation: first.continuation,
      );
      expect(second.continuation, null);
      expect(calls, 2);
      expect(await store.read('youtube:search:music:'), null);
    },
  );

  test('broad queries gain music context without changing music searches or pagination', () async {
    final sent = <Map>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent.add(call.arguments as Map);
      return {
        'tracks': [dto],
        'continuation': 'next',
      };
    });
    for (final entry in {
      'Star Wars': 'Star Wars music',
      'Batman': 'Batman music',
      'Coldplay': 'Coldplay music',
      'Dune OST': 'Dune OST',
      'song lyrics': 'song lyrics',
      'lofi mix': 'lofi mix',
      'full album': 'full album',
      'DJ set': 'DJ set',
      'official AUDIO': 'official AUDIO',
      'musical theatre': 'musical theatre music',
    }.entries) {
      final first = await repo.search(entry.key);
      expect(sent.last['query'], entry.value);
      await repo.search(entry.key, continuation: first.continuation);
      expect(sent.last['query'], entry.value);
      expect(sent.last['continuation'], 'next');
    }
    final before = sent.length;
    expect((await repo.search('  ')).tracks, isEmpty);
    expect(sent.length, before);
    await expectLater(repo.search('x' * 301), throwsA(isA<SourceException>()));
    await repo.search('x' * 300);
    expect((sent.last['query'] as String).length, 300);
  });

  test(
    'music search preserves upstream relevance and caches results',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        expect((call.arguments as Map)['query'], 'Batman music');
        return {
          'tracks': [
            {...dto, 'videoId': 'aaaaaaaaaaa', 'uploader': 'Other artist'},
            {...dto, 'videoId': 'bbbbbbbbbbb', 'uploader': 'Composer - Topic'},
            {...dto, 'videoId': 'ccccccccccc', 'uploader': 'ArtistVEVO'},
            {
              ...dto,
              'videoId': 'ddddddddddd',
              'title': 'Theme (Official Audio)',
            },
            {...dto, 'videoId': 'eeeeeeeeeee', 'uploader': 'Another artist'},
          ],
          'continuation': 'music-page',
        };
      });
      final first = await repo.search('Batman');
      expect(first.tracks.map((t) => t.providerId), [
        'aaaaaaaaaaa',
        'bbbbbbbbbbb',
        'ccccccccccc',
        'ddddddddddd',
        'eeeeeeeeeee',
      ]);
      expect(first.continuation, 'music-page');
      final cached = await repo.search('Batman');
      expect(cached.tracks.map((t) => t.id), first.tracks.map((t) => t.id));
      expect(calls, 1);
    },
  );

  test(
    'empty filtered pages retain their continuation for further music results',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => {
          'tracks': (call.arguments as Map)['continuation'] == null
              ? []
              : [dto],
          'continuation': (call.arguments as Map)['continuation'] == null
              ? 'next-music-page'
              : null,
        },
      );
      final first = await repo.search('Batman');
      expect(first.tracks, isEmpty);
      expect(first.continuation, 'next-music-page');
      final second = await repo.search(
        'Batman',
        continuation: first.continuation,
      );
      expect(second.tracks, hasLength(1));
      expect(second.continuation, isNull);
    },
  );

  test(
    'resolved signed URL and headers stay out of serialized playlists',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'track': dto,
          'url': 'https://media.example/audio?signature=secret',
          'headers': {'X-Test': 'temporary'},
          'mimeType': 'audio/mp4',
          'codec': 'mp4a',
          'expiresAt': DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        },
      );
      final result = await repo.resolve(reference);
      expect(result.stream.headers['X-Test'], 'temporary');
      expect(result.stream.mimeType, 'audio/mp4');
      expect(result.track.uri, reference.uri);
      final playlists = PlaylistsRepository(store);
      await playlists.save([
        Playlist('p', 'Test', [result.track]),
      ]);
      final saved = (await store.read('playlists')).toString();
      expect(saved, isNot(contains('secret')));
      expect(saved, isNot(contains('X-Test')));
      expect(
        (await playlists.all()).single.tracks.single.source,
        MediaSource.youtube,
      );
      expect(repo.cacheEntries, 0);
    },
  );

  test('rate limit retries twice and honors bounded retry timing', () async {
    var calls = 0;
    final waits = <Duration>[];
    repo = YouTubeRepository(
      store,
      channel: channel,
      delay: (d) async {
        waits.add(d);
      },
    );
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      throw PlatformException(code: 'rate_limit', details: {'retryAfter': 999});
    });
    await expectLater(
      repo.search('music'),
      throwsA(
        isA<SourceException>().having((e) => e.code, 'code', 'rate_limit'),
      ),
    );
    expect(calls, 3);
    expect(waits, [const Duration(seconds: 8), const Duration(seconds: 8)]);
  });

  test(
    'restrictions and parser failures are sanitized and never retried',
    () async {
      for (final code in [
        'restricted',
        'unavailable',
        'extractor',
        'unsupported_format',
      ]) {
        var calls = 0;
        messenger.setMockMethodCallHandler(channel, (_) async {
          calls++;
          throw PlatformException(code: code, message: 'secret signed URL');
        });
        await expectLater(
          repo.resolve(reference),
          throwsA(
            isA<SourceException>().having(
              (e) => e.message,
              'sanitized',
              isNot(contains('secret')),
            ),
          ),
        );
        expect(calls, 1);
      }
    },
  );

  test(
    'cancellation reaches native request and stale response is discarded',
    () async {
      final pending = Completer<Map<String, Object?>>();
      final cancelled = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'cancel') {
          cancelled.complete();
          return null;
        }
        return pending.future;
      });
      final token = CancelToken();
      final operation = repo.search('music', cancel: token);
      final assertion = expectLater(operation, throwsA(isA<DioException>()));
      await Future<void>.delayed(Duration.zero);
      token.cancel();
      await cancelled.future;
      pending.complete({
        'tracks': [dto],
      });
      await assertion;
      expect(repo.cacheEntries, 0);
    },
  );

  test('legacy disabled setting no longer gates discovery and quality survives restart', () async {
    await store.write('youtubeEnabled', false);
    await repo.configure(quality: StreamQuality.dataSaver);
    final restored = YouTubeRepository(store, channel: channel);
    await restored.loadSettings();
    expect(restored.quality, StreamQuality.dataSaver);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'tracks': [dto],
        'continuation': null,
      },
    );
    expect((await restored.search('music')).tracks, isNotEmpty);
  });

  test('expired or non-HTTPS streams and invalid IDs are rejected', () async {
    for (final data in [
      {'track': dto, 'url': 'http://media.example/audio'},
      {'track': dto, 'url': 'https://media.example/audio', 'expiresAt': 1},
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => data);
      await expectLater(
        repo.resolve(reference),
        throwsA(isA<SourceException>()),
      );
    }
    await expectLater(
      repo.resolve(
        const Track(id: 'youtube:invalid', title: '', artist: '', uri: ''),
      ),
      throwsA(isA<SourceException>()),
    );
  });

  test('legacy local records retain identity', () {
    final local = Track.fromJson({
      'id': 'local:external:42',
      'title': 'Local',
      'artist': 'A',
      'uri': 'content://media/external/audio/media/42',
    });
    expect(local.source, MediaSource.local);
    expect(reference.source, MediaSource.youtube);
  });
}
