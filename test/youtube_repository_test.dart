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
      expect(store.cacheEntries, 0);
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
      expect(store.cacheEntries, 0);
    },
  );

  test(
    'disabled source rejects cached results and settings survive restart',
    () async {
      await repo.configure(enabled: false, quality: StreamQuality.dataSaver);
      final restored = YouTubeRepository(store, channel: channel);
      await restored.loadSettings();
      expect(restored.enabled, false);
      expect(restored.quality, StreamQuality.dataSaver);
      await expectLater(
        restored.search('music'),
        throwsA(
          isA<SourceException>().having((e) => e.code, 'code', 'disabled'),
        ),
      );
    },
  );

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

  test('legacy Audius and local records migrate without losing identity', () {
    final local = Track.fromJson({
      'id': 'local:external:42',
      'title': 'Local',
      'artist': 'A',
      'uri': 'content://media/external/audio/media/42',
    });
    expect(local.source, MediaSource.local);
    final audius = Track.fromJson({
      'id': 'audius:xyz',
      'title': 'Audius track',
      'artist': 'Audius',
      'uri': 'https://api.audius.co/v1/tracks/xyz/stream?api_key=old',
      'online': true,
    });
    expect(audius.source, MediaSource.audius);
    expect(audius.providerId, 'xyz');
    expect(audius.toSavedJson().toString(), isNot(contains('api_key')));
    expect(reference.source, MediaSource.youtube);
  });
}
