import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/store.dart';
import 'package:svara/core/media_source.dart';
import 'package:svara/features/discovery/ranked_discovery.dart';
import 'package:svara/features/discovery/regional_youtube_catalog.dart';
import 'package:svara/features/discovery/youtube_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  const channel = MethodChannel('test.regional/charts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Store store;
  late YouTubeRepository youtube;
  late RegionalYouTubeCatalog catalog;
  var now = DateTime.utc(2026, 10, 12);
  var calls = <String>[];
  Map<String, dynamic> response(String country) => {
    'country': country,
    'ownerUrl': 'https://www.youtube.com/channel/UCrKZcyOJVWnJ60zM1XWllNw',
    'name':
        'Top 100 Songs ${RegionalYouTubeCatalog.markets[country.toLowerCase()]}',
    'sourceUrl':
        'https://www.youtube.com/playlist?list=${RegionalYouTubeCatalog.playlistIds[country.toLowerCase()]}',
    'tracks': List.generate(
      21,
      (i) => {
        'videoId': i.toString().padLeft(11, 'a'),
        'title': 'Video $i',
        'uploader': 'Channel $i',
        'rank': i + 1,
        'durationMs': 180000,
        'streamable': i != 2,
      },
    ),
  };
  setUp(() async {
    calls = [];
    now = DateTime.utc(2026, 10, 12);
    store = await Store.open(path: inMemoryDatabasePath);
    youtube = YouTubeRepository(store, channel: channel, delay: (_) async {});
    catalog = RegionalYouTubeCatalog(youtube, now: () => now);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      expect(call.method, 'musicCharts');
      return response((call.arguments as Map)['country'] as String);
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    catalog.dispose();
    await store.db.close();
  });
  test(
    'regional chart identity is played directly without candidate search',
    () async {
      final page = await catalog.page(market: 'in');
      final matches = await RankedMatcher(youtube)
          .matchPage(page, CancelToken());
      expect(calls, ['musicCharts']);
      expect(page.ranking, 'most-played');
      expect(page.entries.map((r) => r.rank), List.generate(10, (i) => i + 1));
      expect(matches[0].track!.id, page.entries[0].id);
      expect(matches[0].track!.catalog!['directChartReference'], true);
      expect(matches[0].track!.catalog!['artists'], isEmpty);
      expect(matches[0].track!.recordingArtist, 'Channel 0');
      expect(matches[2].track, isNull);
      expect(page.updatedAt, isNull);
    },
  );
  test(
    'pagination pins regional snapshot and expires after fifteen minutes',
    () async {
      final first = await catalog.page(market: 'gb');
      final second = await catalog.page(market: 'gb', cursor: first.cursor);
      expect(calls, ['musicCharts']);
      expect(second.entries.first.rank, 11);
      expect(second.fetchedAt, first.fetchedAt);
      await expectLater(
        catalog.page(market: 'in', cursor: first.cursor),
        throwsFormatException,
      );
      now = now.add(const Duration(minutes: 15));
      await expectLater(
        catalog.page(market: 'gb', cursor: second.cursor),
        throwsFormatException,
      );
    },
  );
  test(
    'deduplication preserves first source rank without renumbering',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        final data = response('IN');
        final rows = data['tracks'] as List;
        rows[1]['videoId'] = rows[0]['videoId'];
        return data;
      });
      final page = await catalog.page(market: 'in');
      expect(page.entries.take(3).map((r) => r.rank), [1, 3, 4]);
    },
  );
  test('different country, owner and malformed ranks cannot become regional charts', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => response('US'));
    await expectLater(catalog.page(market: 'in'), throwsFormatException);
    messenger.setMockMethodCallHandler(channel, (_) async {
      final data = response('IN');
      data['ownerUrl'] = 'https://www.youtube.com/channel/other';
      return data;
    });
    await expectLater(catalog.page(market: 'in'), throwsFormatException);
    messenger.setMockMethodCallHandler(channel, (_) async {
      final data = response('IN');
      (data['tracks'] as List)[1]['rank'] = 1;
      return data;
    });
    await expectLater(catalog.page(market: 'in'), throwsFormatException);
  });
  test('unsupported categories and cancellation make no requests', () async {
    await expectLater(catalog.page(market: 'global'), throwsFormatException);
    await expectLater(
      catalog.page(market: 'in', genre: 'rock'),
      throwsFormatException,
    );
    final cancel = CancelToken()..cancel();
    await expectLater(
      catalog.page(market: 'in', cancel: cancel),
      throwsA(isA<DioException>()),
    );
    expect(calls, isEmpty);
  });
  test(
    'outage remains an error without ListenBrainz or generic search fallback',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls.add('musicCharts');
        throw PlatformException(code: 'rate_limit');
      });
      await expectLater(
        catalog.page(market: 'in'),
        throwsA(isA<SourceException>()),
      );
      expect(calls, ['musicCharts', 'musicCharts', 'musicCharts']);
    },
  );
}
