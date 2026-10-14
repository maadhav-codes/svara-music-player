import 'package:svara/features/discovery/ranked_discovery.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/providers.dart';
import 'package:svara/core/store.dart';
import 'package:svara/features/discovery/discovery_screen.dart';
import 'package:svara/features/discovery/artist_screen.dart';
import 'package:svara/features/discovery/artist_favorites.dart';
import 'package:svara/features/player/svara_handler.dart';

import 'player_test.dart' show MemoryPlayer;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  testWidgets(
    'artist search opens a rich profile, follows persist, albums open and play',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Store store;
      late SvaraHandler handler;
      await tester.runAsync(() async {
        store = await Store.open(path: inMemoryDatabasePath);
        handler = SvaraHandler(store, audioPlayer: MemoryPlayer());
      });
      const channel = MethodChannel('app.svara/youtube');
      final artist = {
        'url': 'https://www.youtube.com/channel/UCaria',
        'name': 'Aria',
        'description': 'Independent vocalist.',
        'subscribers': 432,
      };
      final album = {
        'url': 'https://www.youtube.com/playlist?list=PLone',
        'name': 'Debut album',
        'artist': 'Aria',
        'count': 10,
      };
      final track = {
        'videoId': 'aaaaaaaaaaa',
        'title': 'Quiet song',
        'uploader': 'Aria',
        'uploaderUrl': artist['url'],
      };
      final messenger = tester.binding.defaultBinaryMessenger;
      final queries = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'cancel') return null;
        if (call.method == 'artist') return artist;
        if (call.method == 'resolveAudio') {
          return {
            'studioAudioVerified': true,
            'mimeType': 'audio/mp4',
            'track': track,
            'url': 'https://audio.example/stream',
          };
        }
        if (call.method == 'collection') {
          return {
            'tracks': [track],
            'continuation': null,
          };
        }
        final args = call.arguments as Map;
        queries.add(args['query'] as String);
        return {
          'tracks': [track],
          'artists': [artist],
          'collections': args['kind'] == 'albums' ? [album] : [],
          'continuation': null,
        };
      });
      Future<void> settle() async {
        for (var i = 0; i < 3; i++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)),
          );
        }
        await tester.pumpAndSettle();
      }

      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              discoveryCatalogProvider.overrideWithValue(DiscoveryCatalog()),
              storeProvider.overrideWithValue(store),
              handlerProvider.overrideWithValue(handler),
            ],
            child: const MaterialApp(home: Scaffold(body: DiscoveryScreen())),
          ),
        );
        await settle();
        expect(queries, isEmpty);
        await tester.enterText(find.byType(TextField), 'Aria');
        await tester.pump(const Duration(milliseconds: 400));
        await settle();
        // Unlabeled songs remain visible, then switch using the visible control.
        expect(find.text('Quiet song').hitTestable(), findsOneWidget);
        expect(tester.getTopLeft(find.text('Quiet song')).dy, lessThan(320));
        await tester.tap(find.text('Artists'));
        await settle();
        await tester.tap(find.widgetWithText(ListTile, 'Aria'));
        await settle();
        expect(find.byType(ArtistScreen), findsOneWidget);
        expect(find.text('Independent vocalist.'), findsOneWidget);
        expect(find.text('432 subscribers'), findsOneWidget);
        expect(find.text('Quiet song'), findsOneWidget);
        expect(find.text('Debut album'), findsOneWidget);
        await tester.tap(find.text('Follow artist'));
        await settle();
        expect(find.text('Following'), findsOneWidget);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ArtistScreen)),
        );
        expect(
          container.read(followedArtistsProvider).asData!.value.single.name,
          'Aria',
        );
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Debut album'));
        await tester.tap(find.text('Debut album'));
        await settle();
        expect(find.byType(CollectionScreen), findsOneWidget);
        await tester.tap(find.text('Quiet song'));
        await settle();
        expect(handler.current!.title, 'Quiet song');
        expect(handler.player.playing, true);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        messenger.setMockMethodCallHandler(channel, null);
        await tester.runAsync(() async {
          await handler.dispose();
          await store.db.close();
        });
      }
    },
  );
}
