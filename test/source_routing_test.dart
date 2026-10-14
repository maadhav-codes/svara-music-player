import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/media_source.dart';
import 'package:svara/core/store.dart';
import 'package:svara/core/track.dart';
import 'package:svara/features/discovery/youtube_repository.dart';
import 'package:svara/features/player/svara_handler.dart';

import 'player_test.dart' show MemoryPlayer;

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
        'studioAudioVerified': true,
        'mimeType': 'audio/mp4',
        'track': {
          'videoId': 'aaaaaaaaaaa',
          'title': 'Test',
          'uploader': 'Channel',
        },
        'url': 'https://media.example/audio',
      },
    );
    final player = MemoryPlayer();
    final handler = SvaraHandler(
      store,
      audioPlayer: player,
      resolveYouTube: YouTubeRepository(store, channel: channel).resolve,
    );
    try {
      const local = Track(
        id: 'local:external:42',
        title: 'Local',
        artist: 'A',
        uri: 'content://media/external/audio/media/42',
      );
      await handler.setQueue([local], start: false);
      expect((player.lastSource! as UriAudioSource).uri.toString(), local.uri);
      const yt = Track(
        id: 'youtube:aaaaaaaaaaa',
        title: '',
        artist: '',
        uri: '',
      );
      await handler.setQueue([yt], start: false);
      expect(handler.current!.source, MediaSource.youtube);
      expect(
        (player.lastSource! as UriAudioSource).uri.toString(),
        'https://media.example/audio',
      );
    } finally {
      await handler.dispose();
      messenger.setMockMethodCallHandler(channel, null);
      await store.db.close();
    }
  });
}
