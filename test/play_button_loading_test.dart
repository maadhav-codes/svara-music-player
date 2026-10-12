import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/store.dart';
import 'package:svara/core/media_source.dart';
import 'package:svara/core/track.dart';
import 'package:svara/features/player/player_screen.dart';
import 'package:svara/core/resolved_track.dart';
import 'package:svara/features/player/svara_handler.dart';

import 'player_test.dart' show MemoryPlayer;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  testWidgets(
    'mini and full play buttons show contrasting spinners during skips and buffering',
    (tester) async {
      late Store store;
      late SvaraHandler handler;
      late MemoryPlayer player;
      Completer<ResolvedTrack>? pending;
      late StreamController<Track> resolving;
      await tester.runAsync(() async {
        player = MemoryPlayer();
        resolving = StreamController<Track>.broadcast();
        store = await Store.open(path: inMemoryDatabasePath);
        handler = SvaraHandler(
          store,
          audioPlayer: player,
          resolveYouTube: (track, {cancel, alternative = false}) {
            resolving.add(track);
            return pending?.future ??
                Future.value(
                  ResolvedTrack(
                    track,
                    ResolvedStream(uri: Uri.parse(track.uri)),
                  ),
                );
          },
        );
        await handler.setQueue([
          const Track(
            id: '1',
            title: 'First',
            artist: 'Artist',
            uri: 'content://music/1',
            source: MediaSource.youtube,
          ),
          const Track(
            id: '2',
            title: 'Second',
            artist: 'Artist',
            uri: 'content://music/2',
            source: MediaSource.youtube,
          ),
        ]);
      });
      addTearDown(
        () => tester.runAsync(() async {
          await handler.dispose();
          await resolving.close();
          await store.db.close();
        }),
      );
      final theme = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      );
      Future<void> mount() => tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Row(
              children: [PlayButton(handler), PlayButton(handler, large: true)],
            ),
          ),
        ),
      );
      void expectSpinners() {
        expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
        for (final spinner in tester.widgetList<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        )) {
          expect(spinner.color, theme.colorScheme.onPrimary);
          expect(spinner.color, isNot(theme.colorScheme.primary));
          expect(spinner.semanticsLabel, 'Loading track');
        }
      }

      await mount();
      await tester.pump();
      expect(find.byTooltip('Pause'), findsNWidgets(2));
      pending = Completer<ResolvedTrack>();
      late Future<void> skip;
      late Track selected;
      await tester.runAsync(() async {
        final started = resolving.stream.first;
        skip = handler.skipToNext();
        selected = await started;
      });
      await tester.pump();
      expect(selected.id, '2');
      expectSpinners();
      // Mounting while resolution is pending must immediately reflect loading.
      await tester.pumpWidget(const SizedBox());
      await mount();
      expectSpinners();
      await tester.runAsync(() async {
        pending!.complete(
          ResolvedTrack(selected, ResolvedStream(uri: Uri.parse(selected.uri))),
        );
        await skip;
      });
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byTooltip('Pause'), findsNWidgets(2));

      await tester.runAsync(() async {
        player.state = ProcessingState.buffering;
        player.states.add(player.state);
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expectSpinners();
      await tester.runAsync(() async {
        player.state = ProcessingState.ready;
        player.states.add(player.state);
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);

      pending = Completer<ResolvedTrack>();
      await tester.runAsync(() async {
        final started = resolving.stream.first;
        skip = handler.skipToPrevious();
        selected = await started;
      });
      await tester.pump();
      expect(selected.id, '1');
      expectSpinners();
      await tester.runAsync(() async {
        pending!.completeError(StateError('Unavailable track'));
        await skip;
      });
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byTooltip('Play'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
