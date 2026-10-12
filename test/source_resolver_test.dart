import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/media_source.dart';
import 'package:svara/core/store.dart';
import 'package:svara/core/track.dart';
import 'package:svara/features/discovery/youtube_repository.dart';
import 'package:svara/features/player/source_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test('routes local and YouTube tracks and preserves scoped URIs', () async {
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
    final resolver = SourceResolver(
      youtube: YouTubeRepository(store, channel: channel),
    );
    try {
      const local = Track(
        id: 'local:external:42',
        title: 'Local',
        artist: 'A',
        uri: 'content://media/external/audio/media/42',
      );
      expect((await resolver.resolve(local)).stream.uri.toString(), local.uri);
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
      await store.db.close();
    }
  });
}
