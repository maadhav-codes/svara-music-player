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
          title: 'A little closer',
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
      final boundary = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
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
      expect(find.text('Allow music access / Retry'), findsOneWidget);
      await tester.tap(find.text('Allow music access / Retry'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('Evening raga'), findsOneWidget);
      expect(tester.takeException(), null);
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('docs/library-preview.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.runAsync(() async {
        await handler.setQueue(songs, index: 0, start: false);
      });
      await tester.pumpAndSettle();
      await tester.tap(find.byType(MiniPlayer));
      await tester.pumpAndSettle();
      expect(find.text('Now playing'), findsOneWidget);
      expect(tester.takeException(), null);
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('docs/player-preview.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
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
      expect(find.text('STREAMING FROM YOUTUBE'), findsOneWidget);
      expect(find.text('STREAMING FROM AUDIUS'), findsNothing);
      expect(find.text('Open video in YouTube'), findsOneWidget);
      expect(find.text('0:42'), findsOneWidget);
      expect(tester.takeException(), null);
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
