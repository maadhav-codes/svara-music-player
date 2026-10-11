import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/media_source.dart';
import 'package:svara/core/store.dart';
import 'package:svara/core/track.dart';
import 'package:svara/features/discovery/audius_repository.dart';
import 'package:svara/features/discovery/youtube_repository.dart';
import 'package:svara/features/player/source_resolver.dart';

import 'svara_test.dart' show FakeAdapter;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test(
    'routes each provider, preserves scoped URIs, rejects gated Audius tracks',
    () async {
      final store = await Store.open(path: inMemoryDatabasePath);
      const channel = MethodChannel('test.resolver/youtube');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'track': {
            'videoId': 'aaaaaaaaaaa',
            'title': 'Test',
            'uploader': 'Channel',
          },
          'url': 'https://media.example/audio',
        },
      );
      final dio = Dio(BaseOptions(baseUrl: 'https://example.org'));
      var gated = false;
      dio.httpClientAdapter = FakeAdapter((options, _) {
        expect(options.path, '/v1/tracks/a');
        return ResponseBody.fromString(
          '{"data":{"id":"a","title":"Song","is_stream_gated":$gated}}',
          200,
          headers: {
            'content-type': ['application/json'],
          },
        );
      });
      final resolver = SourceResolver(
        audius: AudiusRepository(store, client: dio),
        youtube: YouTubeRepository(store, channel: channel),
      );
      try {
        const local = Track(
          id: 'local:external:42',
          title: 'Local',
          artist: 'A',
          uri: 'content://media/external/audio/media/42',
        );
        expect(
          (await resolver.resolve(local)).stream.uri.toString(),
          local.uri,
        );
        const audius = Track(
          id: 'audius:a',
          title: 'Audius track',
          artist: 'Audius',
          uri: '',
          online: true,
        );
        expect(
          (await resolver.resolve(audius)).stream.uri.path,
          contains('/a/stream'),
        );
        gated = true;
        store.clearSessionCache();
        await expectLater(
          resolver.resolve(audius),
          throwsA(isA<SourceException>()),
        );
        const yt = Track(
          id: 'youtube:aaaaaaaaaaa',
          title: '',
          artist: '',
          uri: '',
        );
        expect((await resolver.resolve(yt)).track.source, MediaSource.youtube);
        final cancelled = CancelToken()..cancel();
        await expectLater(
          resolver.resolve(local, cancel: cancelled),
          throwsA(isA<DioException>()),
        );
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
        dio.close();
        await store.db.close();
      }
    },
  );
}
