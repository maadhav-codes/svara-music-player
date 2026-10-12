import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svara/features/discovery/listenbrainz_catalog.dart';
import 'package:svara/features/discovery/ranked_discovery.dart';
import 'package:svara/core/track.dart';

const id = '6f33dc05-cdc0-4a2f-8039-e8fed082eec6';
const id2 = '98faaa53-eb11-4a49-9b69-33262055efb7';
const artistUrl = 'https://music.youtube.com/channel/UC1234567890123456789012';
void main() {
  late DateTime clock;
  late Dio dio;
  late ListenBrainzCatalog catalog;
  late List<RequestOptions> calls;
  late List<Duration> delays;
  late Map<String, dynamic> chart;
  late Map<String, dynamic> recording;
  setUp(() {
    clock = DateTime.utc(2026, 10, 12);
    calls = [];
    delays = [];
    chart = {
      'payload': {
        'range': 'week',
        'offset': 0,
        'last_updated': 1791676800,
        'from_ts': 1790553600,
        'to_ts': 1791158400,
        'total_recording_count': 30,
        'recordings': [
          {
            'recording_mbid': id,
            'artist_name': 'BTS',
            'track_name': 'SWIM',
            'release_name': 'ARIRANG',
            'listen_count': 100,
          },
          {
            'recording_mbid': id,
            'artist_name': 'BTS',
            'track_name': 'SWIM',
            'listen_count': 90,
          },
          {
            'recording_mbid': null,
            'artist_name': 'Unknown',
            'track_name': 'Unmapped',
            'listen_count': 80,
          },
        ],
      },
    };
    recording = {
      'id': id,
      'title': 'SWIM',
      'length': 159007,
      'isrcs': ['USA2P2600449'],
      'artist-credit': [
        {'name': 'BTS'},
      ],
      'disambiguation': '',
    };
    dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          calls.add(request);
          expect(request.headers['User-Agent'], ListenBrainzCatalog.userAgent);
          expect(request.headers.containsKey('Authorization'), false);
          handler.resolve(
            Response(
              requestOptions: request,
              data: request.uri.host == 'api.listenbrainz.org'
                  ? chart
                  : recording,
            ),
          );
        },
      ),
    );
    catalog = ListenBrainzCatalog(
      dio: dio,
      now: () => clock,
      delay: (duration) async {
        delays.add(duration);
        clock = clock.add(duration);
      },
    );
  });
  tearDown(() => catalog.dispose());
  test(
    'capabilities offer verified periods, with no invented markets/genres',
    () async {
      final capabilities = await catalog.capabilities();
      expect(capabilities.markets.keys, ['global']);
      expect(capabilities.genres, isEmpty);
      expect(capabilities.scopes.keys, ['week', 'month', 'year']);
      expect(calls, isEmpty);
      await expectLater(catalog.page(market: 'in'), throwsFormatException);
      await expectLater(
        catalog.page(market: 'global', genre: 'rock'),
        throwsFormatException,
      );
      await expectLater(
        catalog.page(market: 'global', scope: 'today'),
        throwsFormatException,
      );
    },
  );
  test(
    'real schema retains order, counts, period, CC0 metadata and deduplication',
    () async {
      final page = await catalog.page(market: 'global');
      expect(page.entries.map((e) => e.rank), [1, 3]);
      expect(page.entries.first.durationMs, 159007);
      expect(page.entries.first.artists, ['BTS']);
      expect(page.entries.first.isrc, 'USA2P2600449');
      expect(page.entries.first.listenCount, 100);
      expect(page.entries.last.durationMs, isNull);
      expect(page.entries.last.isrc, isNull);
      expect(page.entries.first.genres, isEmpty);
      expect(page.cursor, 'week:1791676800:3');
      expect(page.periodStart, DateTime.utc(2026, 9, 28));
      expect(page.periodEnd, DateTime.utc(2026, 10, 5));
      expect(page.updatedAt, DateTime.utc(2026, 10, 11));
      expect(calls.length, 2);
      expect(calls.first.queryParameters.keys, ['range', 'count', 'offset']);
      expect(calls.last.queryParameters['inc'], 'artist-credits+isrcs');
      expect(delays.single.inMilliseconds, 1100);
      await catalog.page(market: 'global');
      expect(
        calls.length,
        3,
      ); // Recording metadata reused; chart fetched afresh.
    },
  );
  test('pagination pins source update and refuses malformed cursors', () async {
    await expectLater(
      catalog.page(market: 'global', cursor: 'month:1791676800:10'),
      throwsFormatException,
    );
    await expectLater(
      catalog.page(market: 'global', cursor: 'week:bad:10'),
      throwsFormatException,
    );
    (chart['payload'] as Map)['offset'] = 10;
    await expectLater(
      catalog.page(market: 'global', cursor: 'week:1791676700:10'),
      throwsFormatException,
    );
    expect(calls.length, 1); // No enrichment on a changed snapshot.
    final page = await catalog.page(
      market: 'global',
      cursor: 'week:1791676800:10',
    );
    expect(page.entries.first.rank, 11);
    expect(page.cursor, 'week:1791676800:13');
  });
  test('counts, wrong scopes and timestamps are validated', () async {
    (chart['payload'] as Map)['range'] = 'year';
    await expectLater(catalog.page(market: 'global'), throwsFormatException);
    (chart['payload'] as Map)['range'] = 'week';
    (chart['payload']['recordings'] as List)[1]['listen_count'] = 200;
    await expectLater(catalog.page(market: 'global'), throwsFormatException);
    (chart['payload']['recordings'] as List)[1]['listen_count'] = 90;
    (chart['payload'] as Map)['to_ts'] = 1790553500;
    await expectLater(catalog.page(market: 'global'), throwsFormatException);
  });
  test('explicit alternate-version identity remains explicit', () async {
    recording['disambiguation'] = 'live acoustic version';
    final page = await catalog.page(market: 'global');
    expect(page.entries.first.version, 'live acoustic version');
  });
  test('metadata outages leave unknown duration; throttling is propagated and obeyed', () async {
    dio.interceptors.clear();
    var metadataFails = true;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, h) {
          calls.add(r);
          if (r.uri.host == 'musicbrainz.org' && metadataFails) {
            h.reject(
              DioException(
                requestOptions: r,
                response: Response(requestOptions: r, statusCode: 404),
              ),
            );
          } else if (metadataFails) {
            h.resolve(Response(requestOptions: r, data: chart));
          } else {
            h.reject(
              DioException(
                requestOptions: r,
                response: Response(
                  requestOptions: r,
                  statusCode: 429,
                  headers: Headers.fromMap({
                    'Retry-After': ['5'],
                  }),
                ),
              ),
            );
          }
        },
      ),
    );
    expect(
      (await catalog.page(market: 'global')).entries.first.durationMs,
      isNull,
    );
    metadataFails = false;
    await expectLater(
      catalog.page(market: 'global'),
      throwsA(isA<DioException>()),
    );
    await expectLater(
      catalog.page(market: 'global'),
      throwsA(isA<DioException>()),
    );
    expect(delays.last.inSeconds, 5);
  });
  test('empty 204 statistics remain an honest empty chart', () async {
    dio.interceptors.clear();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, h) =>
            h.resolve(Response(requestOptions: r, statusCode: 204)),
      ),
    );
    final page = await catalog.page(market: 'global');
    expect(page.entries, isEmpty);
    expect(page.cursor, isNull);
  });
  test('cancellation while queued never launches a second request', () async {
    final hold = Completer<void>();
    final started = Completer<void>();
    dio.interceptors.clear();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, h) async {
          calls.add(r);
          started.complete();
          await hold.future;
          h.resolve(Response(requestOptions: r, statusCode: 204));
        },
      ),
    );
    final first = catalog.page(market: 'global');
    await started.future;
    final cancel = CancelToken();
    final second = catalog.page(market: 'global', cancel: cancel);
    final expectation = expectLater(second, throwsA(isA<DioException>()));
    cancel.cancel();
    hold.complete();
    await first;
    await expectation;
    expect(calls.length, 1);
  });
  test(
    'YouTube Music artist evidence accepts artist-labelled catalog rows only',
    () {
      const song = CatalogRecording(
        id: id,
        title: 'SWIM',
        artists: ['BTS'],
        rank: 1,
        durationMs: 159007,
        sourceUrl: 'https://listenbrainz.org/statistics/',
      );
      Track row({
        bool catalog = true,
        String url = artistUrl,
        String artist = 'BTS',
        String title = 'SWIM',
      }) => Track(
        id: 'youtube:qZTVU04UOO4',
        title: title,
        artist: artist,
        uri: 'https://www.youtube.com/watch?v=qZTVU04UOO4',
        durationMs: 160000,
        musicCatalogSong: catalog,
        uploaderUrl: url,
      );
      expect(RankedMatcher.confidence(song, row()), .95);
      expect(RankedMatcher.confidence(song, row(catalog: false)), 0);
      expect(
        RankedMatcher.confidence(
          song,
          row(url: 'https://other.example/channel/UC1234567890123456789012'),
        ),
        0,
      );
      expect(
        RankedMatcher.confidence(
          song,
          row(
            artist: 'ZZang KARAOKE',
            title: 'SWIM (Instrumental Karaoke Version)',
          ),
        ),
        0,
      );
      expect(RankedMatcher.confidence(song, row(title: 'SWIM (Remix)')), 0);
      final saved = Track.fromJson(row().toSavedJson());
      expect(saved.musicCatalogSong, true);
      expect(saved.uploaderUrl, artistUrl);
    },
  );
  test(
    'missing credited artist data cannot produce a playable duration match',
    () async {
      recording['artist-credit'] = [];
      final page = await catalog.page(market: 'global');
      expect(page.entries.first.durationMs, isNull);
      const invalid = CatalogRecording(
        id: id,
        title: 'SWIM',
        artists: [],
        rank: 1,
        durationMs: 159007,
        sourceUrl: 'https://listenbrainz.org/statistics/',
      );
      const candidate = Track(
        id: 'youtube:qZTVU04UOO4',
        title: 'SWIM',
        artist: 'BTS',
        uri: 'https://www.youtube.com/watch?v=qZTVU04UOO4',
        durationMs: 160000,
        musicCatalogSong: true,
        uploaderUrl: artistUrl,
      );
      expect(RankedMatcher.confidence(invalid, candidate), 0);
    },
  );
}
