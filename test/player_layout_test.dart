import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/media_source.dart';
import 'package:svara/core/providers.dart';
import 'package:svara/core/store.dart';
import 'package:svara/core/track.dart';
import 'package:svara/features/player/player_screen.dart';
import 'package:svara/features/player/svara_handler.dart';

import 'player_test.dart' show MemoryPlayer;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  testWidgets(
    'full player keeps seek and playback controls visible across screen sizes and text scales',
    (tester) async {
      late Store store;
      late SvaraHandler handler;
      await tester.runAsync(() async {
        store = await Store.open(path: inMemoryDatabasePath);
        handler = SvaraHandler(store, audioPlayer: MemoryPlayer());
        await handler.setQueue([
          const Track(
            id: 'local:1',
            title: 'A long song title for a quiet evening with music',
            artist: 'An artist with a long name',
            uri: 'content://music/1',
            durationMs: 180000,
          ),
        ], start: false);
      });
      const channel = MethodChannel('app.svara/media');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() async {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        messenger.setMockMethodCallHandler(channel, null);
        await handler.dispose();
        await store.db.close();
      });
      for (final source in [
        MediaSource.local,
        MediaSource.audius,
        MediaSource.youtube,
      ]) {
        // Metadata can change sources without asking the test audio player to resolve a network stream.
        handler.tracks[0] = Track(
          id: 'local:1',
          title: 'A long song title for a quiet evening with music',
          artist: 'An artist with a long name',
          uri: 'content://music/1',
          source: source,
          durationMs: 180000,
        );
        for (final size in [
          const Size(320, 568),
          const Size(360, 640),
          const Size(390, 844),
          const Size(640, 360),
          const Size(844, 390),
        ]) {
          for (final scale in [1.0, 2.0]) {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  storeProvider.overrideWithValue(store),
                  handlerProvider.overrideWithValue(handler),
                ],
                child: MaterialApp(
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale),
                      padding: const EdgeInsets.only(top: 24, bottom: 24),
                    ),
                    child: child!,
                  ),
                  home: const PlayerScreen(),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final label = '$source, $size, text scale $scale';
            expect(tester.takeException(), isNull, reason: label);
            for (final tooltip in [
              'Play',
              'Previous track',
              'Next track',
              'Shuffle',
              'Repeat: none',
            ]) {
              final control = find.byTooltip(tooltip);
              expect(control.hitTestable(), findsOneWidget, reason: label);
              expect(
                tester.getBottomRight(control).dy,
                lessThanOrEqualTo(size.height - 24),
                reason: label,
              );
            }
            expect(
              find.byType(Slider).hitTestable(),
              findsOneWidget,
              reason: label,
            );
            if (scale == 1 && size.width < size.height) {
              final scroll = tester.state<ScrollableState>(
                find.descendant(
                  of: find.byType(SingleChildScrollView),
                  matching: find.byType(Scrollable),
                ),
              );
              expect(
                scroll.position.maxScrollExtent,
                closeTo(0, 1),
                reason: label,
              );
            }
            await tester.pumpWidget(const SizedBox());
          }
        }
      }
    },
  );
}
