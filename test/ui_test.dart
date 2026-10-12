import 'package:svara/features/discovery/ranked_discovery.dart';
import 'package:svara/features/discovery/regional_youtube_catalog.dart';
import 'package:dio/dio.dart';

import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/providers.dart';
import 'package:svara/core/store.dart';
import 'package:svara/core/track.dart';
import 'package:svara/features/player/svara_handler.dart';
import 'package:svara/svara_app.dart';
import 'package:svara/features/player/player_screen.dart';

import 'player_test.dart' show MemoryPlayer;

class PreviewCatalog extends DiscoveryCatalog {
  @override
  bool get configured => true;
  @override
  Future<BrowseCapabilities> capabilities({CancelToken? cancel}) async =>
      const BrowseCapabilities(
        RegionalYouTubeCatalog.markets,
        [],
        scopes: {'week': 'Weekly Top 100'},
        browseTitle: 'Popular songs',
      );
  @override
  Future<RankedPage> page({
    required String market,
    String? genre,
    String scope = 'week',
    String? cursor,
    CancelToken? cancel,
  }) async => RankedPage(
    entries: const [
      CatalogRecording(
        id: 'preview',
        title: 'Quiet song',
        artists: [],
        rank: 1,
        durationMs: 180000,
        sourceUrl: 'https://www.youtube.com/playlist?list=PL4fGSI1pDJn4pTWyM3t61lOyZ6_4jcNOw',
        playback: Track(
          id: 'youtube:aaaaaaaaaaa',
          title: 'Quiet song',
          artist: 'Aria',
          durationMs: 180000,
          uri: 'https://www.youtube.com/watch?v=aaaaaaaaaaa',
        ),
      ),
    ],
    sourceName: 'YouTube Charts (preview)',
    market: market,
    scope: scope,
    fetchedAt: DateTime.utc(2026, 10, 12),
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    chartUrl: 'https://www.youtube.com/playlist?list=PL4fGSI1pDJn4pTWyM3t61lOyZ6_4jcNOw',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  testWidgets(
    'denied permission can retry; real library screen renders without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Store store;
      late SvaraHandler handler;
      await tester.runAsync(() async {
        final configFile = File('.dart_tool/package_config.json').absolute;
        final config = jsonDecode(await configFile.readAsString()) as Map;
        final flutter = (config['packages'] as List).cast<Map>().firstWhere(
          (p) => p['name'] == 'flutter',
        );
        final packageUri = configFile.uri.resolve(flutter['rootUri'] as String);
        final fonts = Uri.parse('${packageUri.toString()}/')
            .resolve('../../bin/cache/artifacts/material_fonts/');
        for (final pair in {
          'Roboto': 'Roboto-Regular.ttf',
          'MaterialIcons': 'MaterialIcons-Regular.otf',
        }.entries) {
          final loader = FontLoader(pair.key)
            ..addFont(
              File.fromUri(fonts.resolve(pair.value))
                  .readAsBytes()
                  .then((b) => ByteData.sublistView(b)),
            );
          await loader.load();
        }
        store = await Store.open(path: inMemoryDatabasePath);
        handler = SvaraHandler(store, audioPlayer: MemoryPlayer());
        await handler.restore();
      });
      var permission = false;
      final songs = [
        const Track(
          id: '1',
          title: 'Evening raga',
          artist: 'Device test artist',
          album: 'Quiet hours',
          durationMs: 180000,
          uri: 'content://media/external/audio/media/1',
        ),
        const Track(
          id: '2',
          title: 'Kaho Na Kaho - Original Motion Picture Soundtrack',
          artist: 'Device test artist',
          album: 'Quiet hours',
          durationMs: 180000,
          uri: 'content://media/external/audio/media/2',
        ),
        const Track(
          id: '3',
          title: 'First light',
          artist: 'Device test artist',
          album: 'Quiet hours',
          durationMs: 180000,
          uri: 'content://media/external/audio/media/3',
        ),
      ];
      const channel = MethodChannel('app.svara/media');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'requestPermission') {
              permission = true;
              return true;
            }
            if (call.method == 'hasPermission') return permission;
            if (call.method == 'scan') {
              return {
                'changed': songs.map((t) => t.toJson()).toList(),
                'ids': ['1', '2', '3'],
              };
            }
            return null;
          });
      const youtubeChannel = MethodChannel('app.svara/youtube');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        youtubeChannel,
        (call) async {
          if (call.method == 'cancel') return null;
          if (call.method == 'resolveAudio') {
            return {
              'url': 'https://audio.example/stream',
              'track': {
                'videoId': 'aaaaaaaaaaa',
                'title': 'Test video',
                'uploader': 'Test uploader',
                'durationMs': 90000,
              },
            };
          }
          return {
            'tracks': [
              {
                'videoId': 'aaaaaaaaaaa',
                'title': 'Quiet song',
                'uploader': 'Aria - Topic',
                'durationMs': 180000,
              },
            ],
            'continuation': null,
          };
        },
      );
      final boundary = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discoveryCatalogProvider.overrideWithValue(PreviewCatalog()),
            storeProvider.overrideWithValue(store),
            handlerProvider.overrideWithValue(handler),
          ],
          child: RepaintBoundary(key: boundary, child: const SvaraApp()),
        ),
      );
      // SQLite FFI runs outside the fake widget clock.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      Future<void> captureThemes(String screen) async {
        final container = ProviderScope.containerOf(boundary.currentContext!);
        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          await tester.runAsync(
            () => container.read(themeProvider.notifier).set(mode),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$screen ${mode.name}',
          );
          await tester.runAsync(() async {
            final image = await render.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final suffix = mode == ThemeMode.light ? '' : '-dark';
            await File('docs/$screen-preview$suffix.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.runAsync(
          () => container.read(themeProvider.notifier).set(ThemeMode.light),
        );
        await tester.pumpAndSettle();
      }

      await captureThemes('library-empty');
      expect(find.text('Allow music access'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('Open app settings'), findsNothing);
      await tester.tap(find.text('Allow music access'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('Evening raga'), findsOneWidget);
      expect(tester.takeException(), null);
      for (final destination in [
        ('Library', Icons.library_music_outlined),
        ('Discover', Icons.explore_outlined),
        ('Playlists', Icons.queue_music),
      ]) {
        final nav = find.byType(NavigationBar);
        final label = find.descendant(
          of: nav,
          matching: find.text(destination.$1),
        );
        final icon = find.descendant(
          of: nav,
          matching: find.byIcon(destination.$2),
        );
        expect(
          tester.getCenter(icon).dx,
          closeTo(tester.getCenter(label).dx, 0.1),
        );
      }
      await captureThemes('library');
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Discover'),
        ),
      );
      await tester.pumpAndSettle();
      await captureThemes('discovery-browse');
      await tester.enterText(find.byType(TextField), 'quiet song');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      await captureThemes('discovery-search');
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Playlists'),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      await captureThemes('playlists-empty');
      await tester.tap(find.text('Discover music'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Library'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await handler.setQueue(songs, index: 0, start: false);
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() => handler.seek(const Duration(seconds: 45)));
      await tester.pumpAndSettle();
      await captureThemes('mini-player');
      await tester.tap(find.byType(MiniPlayer));
      await tester.pumpAndSettle();
      expect(find.text('Now playing'), findsOneWidget);
      expect(tester.takeException(), null);
      await captureThemes('player');
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close player'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Private by design'), findsOneWidget);
      expect(tester.takeException(), null);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await handler.setQueue(
          [
            const Track(
              id: 'youtube:aaaaaaaaaaa',
              title: 'Test video',
              artist: 'Test uploader',
              uri: 'https://www.youtube.com/watch?v=aaaaaaaaaaa',
              durationMs: 90000,
            ),
          ],
          position: const Duration(seconds: 42),
          start: false,
        );
      });
      await tester.pumpAndSettle();
      await tester.tap(find.byType(MiniPlayer));
      await tester.pumpAndSettle();
      expect(find.text('STREAMING FROM YOUTUBE'), findsNothing);
      expect(find.text('Open video in YouTube'), findsNothing);
      await tester.tap(find.byTooltip('Song options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Track Info'));
      await tester.pumpAndSettle();
      expect(find.text('Open in YouTube'), findsOneWidget);
      expect(find.text('Source'), findsOneWidget);
      Navigator.of(tester.element(find.text('Source'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('0:42'), findsOneWidget);
      await captureThemes('online-player');
      expect(tester.takeException(), null);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        youtubeChannel,
        null,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await handler.dispose();
        await store.db.close();
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
}
