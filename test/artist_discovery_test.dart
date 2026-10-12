import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/providers.dart';
import 'package:svara/core/store.dart';
import 'package:svara/features/discovery/artist.dart';
import 'package:svara/features/discovery/artist_favorites.dart';
import 'package:svara/features/discovery/personalized_feed.dart';
import 'package:svara/features/discovery/youtube_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  const artist = Artist(
    url: 'https://www.youtube.com/channel/UCaria',
    name: 'Aria',
  );
  const channel = MethodChannel('test.artists/youtube');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Store store;
  late YouTubeRepository repo;
  setUp(() async {
    store = await Store.open(path: inMemoryDatabasePath);
    repo = YouTubeRepository(store, channel: channel, delay: (_) async {});
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await store.db.close();
  });

  test(
    'typed search retains recordings without language or genre labels',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => {
          'tracks': [
            {'videoId': 'aaaaaaaaaaa', 'title': 'A song', 'uploader': 'Band'},
            {
              'videoId': 'bbbbbbbbbbb',
              'title': 'Another song',
              'uploader': 'Artist - Topic',
            },
          ],
          'continuation': 'next',
        },
      );
      final page = await repo.search('road trip');
      expect(page.tracks.map((t) => t.title), ['A song', 'Another song']);
      expect(page.continuation, 'next');
    },
  );
  test(
    'artist attribution uses identity when available, not a same-name channel',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'tracks': [
            {
              'videoId': 'aaaaaaaaaaa',
              'title': 'Official',
              'uploader': 'Aria',
              'uploaderUrl': artist.url,
            },
            {
              'videoId': 'bbbbbbbbbbb',
              'title': 'Different channel',
              'uploader': 'Aria',
              'uploaderUrl': 'https://www.youtube.com/channel/other',
            },
            {
              'videoId': 'ccccccccccc',
              'title': 'Topic fallback',
              'uploader': 'Aria - Topic',
            },
          ],
          'continuation': null,
        },
      );
      expect(
        (await repo.search(
          'Aria songs',
          artist: artist,
        )).tracks.map((t) => t.providerId),
        ['aaaaaaaaaaa', 'ccccccccccc'],
      );
    },
  );
  test('catalog kinds and collections retain pagination, metadata and cancellation', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'collection') {
        return {
          'tracks': [
            {'videoId': 'aaaaaaaaaaa', 'title': 'Song', 'uploader': 'Aria'},
          ],
          'continuation': 'page2',
        };
      }
      return {
        'artists': [artist.toJson()],
        'collections': [
          {
            'url': 'https://www.youtube.com/playlist?list=PLone',
            'name': 'Debut',
            'artist': 'Aria',
            'count': 12,
          },
        ],
        'continuation': 'next',
      };
    });
    final artists = await repo.catalog('Aria');
    expect(artists.artists.single.id, artist.id);
    final albums = await repo.catalog(
      'Aria',
      kind: 'albums',
      continuation: 'next',
      artist: artist,
    );
    expect(calls.last.arguments, containsPair('kind', 'albums'));
    expect(albums.collections.single.count, 12);
    final page = await repo.collection(albums.collections.single);
    expect(page.tracks.single.title, 'Song');
    await repo.collection(
      albums.collections.single,
      continuation: page.continuation,
    );
    expect(calls.last.arguments, containsPair('continuation', 'page2'));
    await expectLater(
      repo.catalog('Aria', cancel: CancelToken()..cancel()),
      throwsA(isA<DioException>()),
    );
  });
  test(
    'artist follows persist once and rapid toggles keep the correct state',
    () async {
      var container = ProviderContainer(
        overrides: [storeProvider.overrideWithValue(store)],
      );
      try {
        await container.read(followedArtistsProvider.future);
        final controller = container.read(followedArtistsProvider.notifier);
        await Future.wait([
          controller.toggle(artist),
          controller.toggle(artist),
          controller.toggle(artist),
        ]);
        expect(
          container.read(followedArtistsProvider).asData!.value.single.id,
          artist.id,
        );
        container.dispose();
        container = ProviderContainer(
          overrides: [storeProvider.overrideWithValue(store)],
        );
        expect(
          (await container.read(followedArtistsProvider.future)).single.name,
          artist.name,
        );
        await store.db.execute(
          "CREATE TRIGGER fail_artist BEFORE INSERT ON settings WHEN NEW.key = 'followedArtists' BEGIN SELECT RAISE(ABORT, 'failure'); END",
        );
        await expectLater(
          container.read(followedArtistsProvider.notifier).toggle(artist),
          throwsA(isA<DatabaseException>()),
        );
        expect(
          container.read(followedArtistsProvider).asData!.value,
          hasLength(1),
        );
      } finally {
        container.dispose();
      }
    },
  );
  test(
    'an unavailable radio catalog preserves playable tracks and albums',
    () async {
      await store.write('followedArtists', [artist.toJson()]);
      messenger.setMockMethodCallHandler(channel, (call) async {
        final kind = (call.arguments as Map)['kind'];
        if (kind == 'radios') {
          throw PlatformException(code: 'extractor');
        }
        return {
          'tracks': [
            {'videoId': 'aaaaaaaaaaa', 'title': 'Song', 'uploader': 'Aria'},
          ],
          'collections': [
            {
              'url': 'https://www.youtube.com/playlist?list=PLone',
              'name': 'Debut',
              'artist': 'Aria',
            },
          ],
          'continuation': null,
        };
      });
      final container = ProviderContainer(
        overrides: [
          storeProvider.overrideWithValue(store),
          youtubeProvider.overrideWithValue(repo),
        ],
      );
      try {
        final feed = await container.read(artistFeedProvider.future);
        expect(feed.tracks.single.title, 'Song');
        expect(feed.albums.single.name, 'Debut');
        expect(feed.radios, isEmpty);
        expect(feed.failures, 1);
      } finally {
        container.dispose();
      }
    },
  );

  test('home recommendations react to follows and include tracks, releases and radios', () async {
    final kinds = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      final kind = args['kind'] as String? ?? 'songs';
      kinds.add(kind);
      return {
        'tracks': [
          {'videoId': 'aaaaaaaaaaa', 'title': 'Song', 'uploader': 'Aria'},
        ],
        'collections': [
          {
            'url': 'https://www.youtube.com/playlist?list=PL$kind',
            'name': kind == 'radios' ? 'Aria radio' : 'Debut',
            'artist': 'Aria',
          },
        ],
        'continuation': null,
      };
    });
    final container = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(store),
        youtubeProvider.overrideWithValue(repo),
      ],
    );
    try {
      expect((await container.read(artistFeedProvider.future)).tracks, isEmpty);
      await container.read(followedArtistsProvider.notifier).toggle(artist);
      final feed = await container.read(artistFeedProvider.future);
      expect(feed.tracks.single.title, 'Song');
      expect(feed.albums.single.name, 'Debut');
      expect(feed.radios.single.name, 'Aria radio');
      expect(kinds.toSet(), {'songs', 'albums', 'radios'});
      await container.read(followedArtistsProvider.notifier).toggle(artist);
      expect((await container.read(artistFeedProvider.future)).tracks, isEmpty);
    } finally {
      container.dispose();
    }
  });
}
