import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svara/core/track.dart';
import 'package:svara/features/lyrics/lyrics.dart';
import 'package:svara/features/lyrics/lyrics_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.svara/lyrics');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const track = Track(
    id: 'local:external:1',
    title: 'An original test song',
    artist: 'Test artist',
    album: 'Test album',
    durationMs: 60000,
    uri: 'content://media/external/audio/media/1',
    folder: 'Music/',
  );
  late Dio dio;
  late LyricsRepository repository;
  var calls = 0;
  setUp(() {
    calls = 0;
    dio = Dio(BaseOptions(baseUrl: 'https://lrclib.net/api'));
    repository = LyricsRepository(dio: dio, channel: channel);
    messenger.setMockMethodCallHandler(channel, (_) async => null);
  });
  tearDown(() {
    repository.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });
  void respond(
    Object? data, {
    int status = 200,
    Map<String, List<String>>? headers,
  }) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls++;
          expect(options.path, '/get');
          expect(options.queryParameters['track_name'], track.title);
          expect(options.queryParameters['artist_name'], track.artist);
          expect(options.queryParameters['duration'], 60);
          final response = Response<dynamic>(
            requestOptions: options,
            data: data,
            statusCode: status,
            headers: Headers.fromMap(headers ?? {}),
          );
          if (status >= 400) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: response,
                type: DioExceptionType.badResponse,
              ),
            );
          } else {
            handler.resolve(response);
          }
        },
      ),
    );
  }

  test(
    'LRC offsets, repeated stamps, fractions, metadata and backwards seek',
    () {
      final lyrics = Lyrics.parse(
        '[ar:Test artist]\n[offset:-100]\n[00:02.50][00:04.5]Original chorus\n[00:00.050]Opening\n[00:03.001]\n[00:99.00]Invalid',
        source: 'Local',
      );
      expect(lyrics.lines.map((l) => l.time.inMilliseconds), [
        0,
        2400,
        2901,
        4400,
      ]);
      expect(lyrics.activeIndex(const Duration(milliseconds: 2399)), 0);
      expect(lyrics.activeIndex(const Duration(milliseconds: 2400)), 1);
      expect(lyrics.activeIndex(const Duration(seconds: 8)), 3);
      expect(lyrics.activeIndex(Duration.zero), 0);
      expect(lyrics.lines[2].text, '');
      expect(lyrics.lines.last.text, 'Original chorus');
      final positive = Lyrics.parse(
        '[offset:200]\n[00:01]First',
        source: 'Local',
      );
      expect(positive.activeIndex(Duration.zero), -1);
      expect(positive.lines.single.time.inMilliseconds, 1200);
    },
  );
  test('plain text and malformed timestamps remain readable', () {
    expect(
      Lyrics.parse('Original words\nSecond line', source: 'Local').plain,
      'Original words\nSecond line',
    );
    expect(Lyrics.parse('[ar:Metadata]\n[bad]', source: 'Local').empty, true);
  });
  test(
    'local sidecar wins and no network request is made in airplane mode',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'readLocalLyrics');
        expect((call.arguments as Map)['uri'], track.uri);
        return '[00:01]Local original line';
      });
      respond({});
      final result = await repository.load(track);
      expect(result!.source, 'Local .lrc');
      expect(calls, 0);
    },
  );
  test(
    'missing folder access falls back to API; cache and retry refresh work',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'lyrics'),
      );
      respond({'syncedLyrics': '[00:01]Test line', 'duration': 60});
      expect((await repository.load(track))!.source, 'LRCLIB');
      await repository.load(track);
      expect(calls, 1);
      await repository.load(track, refresh: true);
      expect(calls, 2);
    },
  );
  test('404 is a clean no-match and different duration is rejected', () async {
    respond({}, status: 404);
    expect(await repository.load(track), null);
    dio.interceptors.clear();
    respond({'syncedLyrics': '[00:01]Wrong version', 'duration': 120});
    expect(await repository.load(track), null);
  });
  test(
    '429 honors Retry-After and local lyrics still bypass cooldown',
    () async {
      respond(
        {},
        status: 429,
        headers: {
          'retry-after': ['120'],
        },
      );
      await expectLater(
        repository.load(track),
        throwsA(isA<LyricsException>()),
      );
      await expectLater(
        repository.load(track, refresh: true),
        throwsA(isA<LyricsException>()),
      );
      expect(calls, 1);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => '[00:01]Local line',
      );
      expect((await repository.load(track))!.source, 'Local .lrc');
    },
  );
  test('malformed, oversized, instrumental and plain-only responses', () async {
    respond({'syncedLyrics': 42});
    await expectLater(repository.load(track), throwsA(isA<LyricsException>()));
    dio.interceptors.clear();
    respond({'plainLyrics': 'x' * (LyricsRepository.maxText + 1)});
    await expectLater(repository.load(track), throwsA(isA<LyricsException>()));
    dio.interceptors.clear();
    respond({'instrumental': true});
    expect((await repository.load(track))!.instrumental, true);
    dio.interceptors.clear();
    respond({'plainLyrics': 'Original plain line'});
    expect(
      (await repository.load(track, refresh: true))!.plain,
      'Original plain line',
    );
  });
  test('cancellation prevents a lookup after a slow local read', () async {
    final pending = Completer<String?>();
    messenger.setMockMethodCallHandler(channel, (_) => pending.future);
    final cancel = CancelToken();
    respond({'plainLyrics': 'Line'});
    final task = repository.load(track, cancelToken: cancel);
    final expectation = expectLater(task, throwsA(isA<DioException>()));
    cancel.cancel();
    pending.complete(null);
    await expectation;
    expect(calls, 0);
  });
  test('cache evicts old recordings at twenty entries', () async {
    respond({'syncedLyrics': '[00:01]Test line'});
    await repository.load(track);
    for (var i = 0; i < 20; i++) {
      await repository.load(
        Track(
          id: 'local:$i',
          title: track.title,
          artist: track.artist,
          album: 'Album $i',
          durationMs: track.durationMs,
          uri: track.uri,
        ),
      );
    }
    expect(calls, 21);
    await repository.load(track);
    expect(calls, 22);
  });
  test(
    'edited local sidecars are re-read before cached remote lyrics',
    () async {
      respond({'syncedLyrics': '[00:01]Remote line'});
      await repository.load(track);
      var local = '[00:01]First local line';
      messenger.setMockMethodCallHandler(channel, (_) async => local);
      expect(
        (await repository.load(track))!.lines.single.text,
        'First local line',
      );
      local = '[00:01]Edited local line';
      expect(
        (await repository.load(track))!.lines.single.text,
        'Edited local line',
      );
      expect(calls, 1);
    },
  );
  test('timeout yields actionable connection message', () async {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.receiveTimeout,
          ),
        ),
      ),
    );
    await expectLater(
      repository.load(track),
      throwsA(
        isA<LyricsException>().having(
          (e) => e.message,
          'message',
          contains('connection'),
        ),
      ),
    );
  });
}
