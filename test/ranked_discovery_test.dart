import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/store.dart';
import 'package:svara/core/track.dart';
import 'package:svara/features/discovery/ranked_discovery.dart';
import 'package:svara/features/discovery/youtube_repository.dart';

const song = CatalogRecording(
  id: 'one',
  title: 'Northern Lights',
  artists: ['Aria'],
  rank: 1,
  durationMs: 180000,
  sourceUrl: 'https://example.test/one',
  genres: ['rock'],
);
Track candidate({
  String title = 'Northern Lights',
  String artist = 'Aria - Topic',
  int duration = 180000,
}) => Track(
  id: 'youtube:aaaaaaaaaaa',
  title: title,
  artist: artist,
  durationMs: duration,
  uri: 'https://www.youtube.com/watch?v=aaaaaaaaaaa',
);
RankedPage page(List<CatalogRecording> entries) => RankedPage(
  entries: entries,
  sourceName: 'Test',
  market: 'in',
  fetchedAt: DateTime.now(),
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  test('exact recording accepts missing genre/language labels', () {
    expect(RankedMatcher.confidence(song, candidate()), .95);
    expect(
      RankedMatcher.confidence(
        song,
        candidate(
          title: 'Aria - Northern Lights (Official Audio)',
          artist: 'AriaVEVO',
        ),
      ),
      .95,
    );
  });
  test(
    'wrong versions, unknown durations, uploaders and titles are refused',
    () {
      for (final version in [
        'Cover',
        'Remix',
        'Karaoke',
        'Slowed',
        'Sped up',
        'Live',
        'Reaction',
        'Compilation',
        'Acoustic',
      ]) {
        expect(
          RankedMatcher.confidence(
            song,
            candidate(title: 'Northern Lights ($version)'),
          ),
          0,
          reason: version,
        );
      }
      expect(
        RankedMatcher.confidence(song, candidate(title: 'Northern Light')),
        0,
      );
      expect(
        RankedMatcher.confidence(song, candidate(artist: 'Different - Topic')),
        0,
      );
      expect(RankedMatcher.confidence(song, candidate(artist: 'Aria fan')), 0);
      expect(RankedMatcher.confidence(song, candidate(duration: 0)), 0);
      expect(RankedMatcher.confidence(song, candidate(duration: 160000)), 0);
      expect(
        RankedMatcher.confidence(
          const CatalogRecording(
            id: 'x',
            title: 'Northern Lights',
            artists: ['Aria'],
            rank: 1,
            sourceUrl: 'https://example.test/x',
          ),
          candidate(),
        ),
        0,
      );
    },
  );
  test(
    'explicit alternate version can match but cannot silently become original',
    () {
      const remix = CatalogRecording(
        id: 'remix',
        title: 'Northern Lights',
        version: 'Remix',
        artists: ['Aria'],
        rank: 2,
        durationMs: 180000,
        sourceUrl: 'https://example.test/remix',
      );
      expect(
        RankedMatcher.confidence(
          remix,
          candidate(title: 'Northern Lights Remix'),
        ),
        .95,
      );
      expect(RankedMatcher.confidence(remix, candidate()), 0);
    },
  );
  Map<String, dynamic> chartJson() => {
    'ranking': 'most-played',
    'sourceName': 'Test',
    'market': 'in',
    'genre': 'rock',
    'expiresAt': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
    'entries': [
      for (var i = 1; i <= 2; i++)
        {
          'id': '$i',
          'title': 'A song',
          'artists': ['Aria'],
          'rank': i,
          'genres': ['rock'],
          'sourceUrl': 'https://example.test/$i',
        },
    ],
  };
  test('ranked parser requires order and structured category evidence', () {
    final j = chartJson();
    final parsed = RankedPage.fromJson(j);
    expect(parsed.entries.map((e) => e.rank), [1, 2]);
    expect(parsed.updatedAt, isNull);
    (j['entries'] as List)[1]['genres'] = ['pop'];
    expect(() => RankedPage.fromJson(j), throwsFormatException);
    final reordered = chartJson();
    (reordered['entries'] as List)[1]['rank'] = 1;
    expect(() => RankedPage.fromJson(reordered), throwsFormatException);
    expect(
      () => RankedPage.fromJson({...chartJson(), 'ranking': 'sales'}),
      throwsFormatException,
    );
  });
  test('repeated catalog identities retain first ranked occurrence', () {
    final j = chartJson();
    (j['entries'] as List)[1]['id'] = '1';
    expect(RankedPage.fromJson(j).entries.single.rank, 1);
  });
  test(
    'catalog failures, wrong scope, expired data and cancellation propagate',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response(requestOptions: options, data: chartJson()),
          ),
        ),
      );
      final catalog = DiscoveryCatalog(
        dio: dio,
        endpoint: 'https://example.test',
      );
      expect(
        (await catalog.page(market: 'in', genre: 'rock')).entries.length,
        2,
      );
      await expectLater(
        catalog.page(market: 'us', genre: 'rock'),
        throwsFormatException,
      );
      await expectLater(
        catalog.page(
          market: 'in',
          genre: 'rock',
          cancel: CancelToken()..cancel(),
        ),
        throwsA(isA<DioException>()),
      );
      dio.interceptors.clear();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) => h.resolve(
            Response(
              requestOptions: o,
              data: {...chartJson(), 'expiresAt': '2020-01-01T00:00:00Z'},
            ),
          ),
        ),
      );
      await expectLater(
        catalog.page(market: 'in', genre: 'rock'),
        throwsFormatException,
      );
      dio.interceptors.clear();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) => h.reject(
            DioException(
              requestOptions: o,
              response: Response(requestOptions: o, statusCode: 429),
            ),
          ),
        ),
      );
      await expectLater(
        catalog.page(market: 'in', genre: 'rock'),
        throwsA(isA<DioException>()),
      );
      catalog.dispose();
      final unconfigured = DiscoveryCatalog();
      await expectLater(unconfigured.capabilities(), throwsFormatException);
      unconfigured.dispose();
    },
  );

  const channel = MethodChannel('test.ranked/youtube');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Store store;
  setUp(() async {
    store = await Store.open(path: inMemoryDatabasePath);
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await store.db.close();
  });
  test('bounded asynchronous matching retains chart order, cache, metadata and duplicate rejection', () async {
    final first = Completer<void>();
    var active = 0, peak = 0, searches = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'cancel') return null;
      searches++;
      active++;
      if (active > peak) peak = active;
      final query = (call.arguments as Map)['query'] as String;
      final isFirst = query.contains('Northern');
      if (isFirst) await first.future;
      active--;
      return {
        'tracks': [
          {
            'videoId': isFirst ? 'aaaaaaaaaaa' : 'bbbbbbbbbbb',
            'title': isFirst ? 'Northern Lights' : 'Daybreak',
            'uploader': 'Aria - Topic',
            'durationMs': 180000,
          },
        ],
        'continuation': null,
      };
    });
    const second = CatalogRecording(
      id: 'two',
      title: 'Daybreak',
      artists: ['Aria'],
      rank: 2,
      durationMs: 180000,
      sourceUrl: 'https://example.test/two',
    );
    final matcher = RankedMatcher(YouTubeRepository(store, channel: channel));
    final pending = matcher.matchPage(page([song, second]), CancelToken());
    await Future<void>.delayed(const Duration(milliseconds: 30));
    first.complete();
    final results = await pending;
    expect(peak, 2);
    expect(results.map((m) => m.recording.rank), [1, 2]);
    expect(results.map((m) => m.track!.title), ['Northern Lights', 'Daybreak']);
    final restored = Track.fromJson(results.first.track!.toSavedJson());
    expect(restored.artist, 'Aria - Topic');
    expect(restored.recordingArtist, 'Aria');
    expect(restored.catalog!['sourceUrl'], song.sourceUrl);
    expect(restored.toSavedJson().toString(), isNot(contains('expires=')));
    final again = await matcher.matchPage(
      page([song, second, second]),
      CancelToken(),
    );
    expect(searches, 2);
    expect(again.last.track, isNull);
  });
  test('in-flight cancellation refuses completed candidates and stops later searches', () async {
    final release = Completer<void>();
    final started = Completer<void>();
    var searches = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'cancel') return null;
      searches++;
      if (!started.isCompleted) started.complete();
      await release.future;
      return {
        'tracks': [
          {
            'videoId': 'aaaaaaaaaaa',
            'title': song.title,
            'uploader': 'Aria - Topic',
            'durationMs': 180000,
          },
        ],
        'continuation': null,
      };
    });
    final cancel = CancelToken();
    final matcher = RankedMatcher(YouTubeRepository(store, channel: channel));
    final pending = matcher.matchPage(page([song, song, song]), cancel);
    final expectation = expectLater(pending, throwsA(isA<DioException>()));
    await started.future;
    cancel.cancel();
    release.complete();
    await expectation;
    expect(searches, lessThanOrEqualTo(2));
  });
  test(
    'playback resolution retains catalog evidence and canonical uploader',
    () async {
      final youtube = YouTubeRepository(store, channel: channel);
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => {
          'studioAudioVerified': true,
          'mimeType': 'audio/mp4',
          'track': {
            'videoId': 'aaaaaaaaaaa',
            'title': 'Canonical YouTube title',
            'uploader': 'Aria - Topic',
            'durationMs': 180000,
          },
          'url': 'https://audio.example/temporary',
        },
      );
      final reference = Track.fromJson({
        ...candidate().toJson(),
        'catalog': {
          'id': song.id,
          'title': song.title,
          'artists': song.artists,
          'sourceName': 'Test',
          'sourceUrl': song.sourceUrl,
        },
      });
      final resolved = await youtube.resolve(reference);
      expect(resolved.track.title, 'Canonical YouTube title');
      expect(resolved.track.artist, 'Aria - Topic');
      expect(resolved.track.recordingArtist, 'Aria');
      expect(resolved.track.catalog, reference.catalog);
      expect(
        resolved.track.toSavedJson().toString(),
        isNot(contains('temporary')),
      );
    },
  );
  test('unavailable searches do not substitute and pre-cancelled matching does no work', () async {
    var searches = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      searches++;
      return {'tracks': [], 'continuation': null};
    });
    final matcher = RankedMatcher(YouTubeRepository(store, channel: channel));
    await expectLater(
      matcher.matchPage(page([song]), CancelToken()..cancel()),
      throwsA(isA<DioException>()),
    );
    expect(searches, 0);
    final result = await matcher.matchPage(page([song]), CancelToken());
    expect(result.single.track, isNull);
    expect(result.single.confidence, 0);
  });
}
