import 'package:svara/features/discovery/ranked_discovery.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/providers.dart';
import 'package:svara/core/store.dart';
import 'package:svara/features/discovery/discovery_screen.dart';
import 'package:svara/features/playlists/playlists_screen.dart';
import 'package:svara/features/playlists/playlists_repository.dart';
import 'package:svara/features/player/svara_handler.dart';
import 'package:svara/svara_app.dart';

import 'player_test.dart' show MemoryPlayer;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  testWidgets(
    'tabs preserve searches, results, screen state and scroll positions',
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
        await handler.restore();
        await PlaylistsRepository(store).save([
          for (var i = 0; i < 20; i++) Playlist('p$i', 'Playlist $i', []),
        ]);
      });
      const media = MethodChannel('app.svara/media');
      const youtube = MethodChannel('app.svara/youtube');
      final messenger = tester.binding.defaultBinaryMessenger;
      var searches = 0;
      messenger.setMockMethodCallHandler(media, (call) async {
        if (call.method == 'hasPermission') return true;
        if (call.method == 'scan') return {'changed': [], 'ids': []};
        return null;
      });
      messenger.setMockMethodCallHandler(youtube, (call) async {
        if (call.method == 'cancel') return null;
        searches++;
        final query = (call.arguments as Map)['query'];
        return {
          'tracks': [
            for (var i = 0; i < 30; i++)
              {
                'videoId': 'song${i.toString().padLeft(7, '0')}',
                'title': '$query result $i',
                'uploader': 'Channel',
              },
          ],
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

      Future<void> tab(String label) async {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        await settle();
      }

      ScrollPosition position(Type screen) => tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(screen),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              discoveryCatalogProvider.overrideWithValue(DiscoveryCatalog()),
              storeProvider.overrideWithValue(store),
              handlerProvider.overrideWithValue(handler),
            ],
            child: const SvaraApp(),
          ),
        );
        await settle();
        final discoveryState = tester.state(
          find.byType(DiscoveryScreen, skipOffstage: false),
        );
        final playlistsState = tester.state(
          find.byType(PlaylistsScreen, skipOffstage: false),
        );
        await tab('Discover');
        await tester.enterText(find.byType(TextField), 'quiet piano');
        await tester.pump(const Duration(milliseconds: 400));
        await settle();
        final searchCount = searches;
        expect(find.text('quiet piano music result 0'), findsOneWidget);
        final discoveryScroll = position(DiscoveryScreen);
        discoveryScroll.jumpTo(500);
        await tester.pump();
        await tab('Playlists');
        final playlistScroll = position(PlaylistsScreen);
        playlistScroll.jumpTo(500);
        await tester.pump();
        await tab('Library');
        await tab('Discover');
        expect(
          tester.state(find.byType(DiscoveryScreen)),
          same(discoveryState),
        );
        expect(position(DiscoveryScreen).pixels, 500);
        expect(searches, searchCount);
        position(DiscoveryScreen).jumpTo(0);
        await tester.pump();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'quiet piano',
        );
        await tab('Playlists');
        expect(
          tester.state(find.byType(PlaylistsScreen)),
          same(playlistsState),
        );
        expect(position(PlaylistsScreen).pixels, 500);
        // An edit from another screen refreshes a still-mounted playlists tab.
        final container = ProviderScope.containerOf(
          tester.element(find.byType(Home)),
        );
        await tester.runAsync(() async {
          await PlaylistsRepository(store)
              .save([const Playlist('new', 'Fresh playlist', [])]);
        });
        container.invalidate(playlistsProvider);
        await settle();
        position(PlaylistsScreen).jumpTo(0);
        await tester.pump();
        expect(find.text('Fresh playlist'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        messenger.setMockMethodCallHandler(media, null);
        messenger.setMockMethodCallHandler(youtube, null);
        await tester.runAsync(() async {
          await handler.dispose();
          await store.db.close();
        });
      }
    },
  );
}
