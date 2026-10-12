import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/providers.dart';
import 'package:svara/core/store.dart';
import 'package:svara/core/track.dart';
import 'package:svara/core/media_source.dart';
import 'package:svara/core/resolved_track.dart';
import 'package:svara/features/lyrics/lyrics.dart';
import 'package:svara/features/lyrics/lyrics_repository.dart';
import 'package:svara/features/lyrics/lyrics_screen.dart';
import 'package:svara/features/player/player_screen.dart';
import 'package:svara/features/player/svara_handler.dart';

import 'player_test.dart' show MemoryPlayer;

class PositionPlayer extends MemoryPlayer {
  final ticks = StreamController<Duration>.broadcast(sync: true);
  @override
  Stream<Duration> get positionStream => ticks.stream;
  void advance(Duration value) {
    at = value;
    ticks.add(value);
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    await ticks.close();
  }
}

class TestLyricsRepository extends LyricsRepository {
  final pending = <String, Completer<Lyrics?>>{};
  @override
  Future<Lyrics?> load(
    Track track, {
    CancelToken? cancelToken,
    bool refresh = false,
  }) => pending.putIfAbsent(track.id, Completer<Lyrics?>.new).future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  const first = Track(
    id: 'youtube:aaaaaaaaaaa',
    title: 'Original title',
    artist: 'Original artist',
    uri: 'https://www.youtube.com/watch?v=aaaaaaaaaaa',
    durationMs: 60000,
  );
  const second = Track(
    id: 'youtube:bbbbbbbbbbb',
    title: 'Second title',
    artist: 'Another artist',
    uri: 'https://www.youtube.com/watch?v=bbbbbbbbbbb',
    durationMs: 60000,
  );
  testWidgets(
    'lyrics entry points, stale lookup, paused position, seek and large text',
    (tester) async {
      late Store store;
      late SvaraHandler handler;
      final repository = TestLyricsRepository();
      late PositionPlayer player;
      await tester.runAsync(() async {
        store = await Store.open(path: inMemoryDatabasePath);
        player = PositionPlayer();
        handler = SvaraHandler(
          store,
          audioPlayer: player,
          resolveYouTube: (track, {cancel, alternative = false}) async =>
              ResolvedTrack(track, ResolvedStream(uri: Uri.parse(track.uri))),
        );
        await handler.setQueue(
          [first],
          position: const Duration(seconds: 12),
          start: false,
        );
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storeProvider.overrideWithValue(store),
            handlerProvider.overrideWithValue(handler),
            lyricsRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: PlayerScreen()),
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Lyrics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Lyrics'), findsOneWidget);
      // Switch recordings while the old request is still in flight.
      await tester.runAsync(
        () => handler.setQueue(
          [second],
          position: const Duration(seconds: 12),
          start: false,
        ),
      );
      await tester.pump();
      repository.pending[first.id]!.complete(
        Lyrics.parse('[00:00]Stale words', source: 'LRCLIB'),
      );
      repository.pending[second.id]!.complete(
        Lyrics.parse(
          '[00:01]Opening words\n[00:10]Current words\n[00:20]Later words',
          source: 'LRCLIB',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Stale words'), findsNothing);
      expect(find.text('Lyrics from LRCLIB'), findsOneWidget);
      final currentText = tester.widget<Text>(find.text('Current words'));
      final context = tester.element(find.text('Current words'));
      expect(currentText.style!.color, Theme.of(context).colorScheme.primary);
      expect(handler.player.playing, false);
      await tester.tap(find.text('Opening words'));
      await tester.pump();
      expect(handler.position, const Duration(seconds: 1));
      expect(handler.player.playing, false);
      await tester.runAsync(handler.play);
      player.advance(const Duration(seconds: 21));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('Later words')).style!.color,
        Theme.of(tester.element(find.text('Later words'))).colorScheme.primary,
      );
      await tester.runAsync(handler.pause);
      await tester.pumpAndSettle();
      expect(handler.player.playing, false);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pageBack();
      await tester.pumpAndSettle();
      // The artwork supports an upward swipe in addition to the icon.
      await tester.fling(
        find.byKey(const ValueKey('player-artwork')),
        const Offset(0, -100),
        700,
      );
      await tester.pumpAndSettle();
      expect(find.text('Lyrics'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await handler.dispose();
        await store.db.close();
      });
      repository.dispose();
    },
  );
}
