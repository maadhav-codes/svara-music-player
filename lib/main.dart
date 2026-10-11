import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/store.dart';
import 'core/licenses.dart';
import 'core/providers.dart';
import 'features/player/svara_handler.dart';
import 'svara_app.dart';
import 'features/discovery/audius_repository.dart';
import 'features/discovery/youtube_repository.dart';
import 'features/player/source_resolver.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerNativeLicenses();
  final store = await Store.open();
  final audius = AudiusRepository(store);
  final youtube = YouTubeRepository(store);
  await youtube.loadSettings();
  final resolver = SourceResolver(audius: audius, youtube: youtube);
  final handler = await AudioService.init<SvaraHandler>(
    builder: () => SvaraHandler(store, resolve: resolver.resolve),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'app.svara.playback',
      androidNotificationChannelName: 'Svara playback',
      androidNotificationIcon: 'drawable/ic_notification_svara',
      androidNotificationOngoing: true,
    ),
  );
  await handler.initialize();
  runApp(
    ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
        handlerProvider.overrideWithValue(handler),
        audiusProvider.overrideWithValue(audius),
        youtubeProvider.overrideWithValue(youtube),
      ],
      child: const SvaraApp(),
    ),
  );
}
