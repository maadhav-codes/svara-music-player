import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/providers.dart';
import 'package:svara/core/store.dart';
import 'package:svara/core/track.dart';
import 'package:svara/features/library/library_repository.dart';
import 'package:svara/features/library/library_screen.dart';
import 'package:svara/features/player/svara_handler.dart';

import 'player_test.dart' show MemoryPlayer;

class TestLibrary extends LibraryRepository {
  TestLibrary(super.store);
  int reads = 0, scans = 0;
  Completer<void>? scan;
  final tracks = [
    for (var i = 0; i < 501; i++)
      Track(
        id: 'local:$i',
        title: 'Song ${i.toString().padLeft(3, '0')}',
        artist: 'Artist',
        album: 'Album',
        uri: 'content://music/$i',
      ),
  ];
  @override
  Future<bool> permission({bool request = false}) async => true;
  @override
  Future<List<Track>> all() async {
    reads++;
    return tracks;
  }

  @override
  Future<void> refresh() async {
    scans++;
    await scan?.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  testWidgets(
    'all tracks load once; search, sorting, filters and library mix do not reload',
    (tester) async {
      late Store store;
      late SvaraHandler handler;
      await tester.runAsync(() async {
        store = await Store.open(path: inMemoryDatabasePath);
        handler = SvaraHandler(store, audioPlayer: MemoryPlayer());
      });
      final repo = TestLibrary(store)..scan = Completer<void>();
      Future<void> settle() async {
        for (var i = 0; i < 3; i++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)),
          );
        }
        await tester.pumpAndSettle();
      }

      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              storeProvider.overrideWithValue(store),
              handlerProvider.overrideWithValue(handler),
              libraryRepositoryProvider.overrideWithValue(repo),
            ],
            child: const MaterialApp(home: Scaffold(body: LibraryScreen())),
          ),
        );
        await tester.pump();
        expect(repo.reads, 1);
        expect(repo.scans, 1);
        // Pull-to-refresh during the scan must share the outstanding refresh.
        final refresh = tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh();
        await tester.pump();
        expect(repo.scans, 1);
        repo.scan!.complete();
        await refresh;
        await settle();
        expect(repo.reads, 2); // Persisted snapshot and refreshed snapshot.
        expect(find.text('501 tracks'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'Songs'), findsNothing);
        expect(find.widgetWithText(ChoiceChip, 'Favorites'), findsNothing);
        expect(find.text('Load more music'), findsNothing);
        await tester.enterText(find.byType(TextField), 'Song 500');
        await tester.pumpAndSettle();
        expect(find.widgetWithText(SongTile, 'Song 500'), findsOneWidget);
        await tester.tap(find.byTooltip('Sort songs'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Duration'));
        await tester.pumpAndSettle();
        expect(repo.reads, 2);
        await tester.enterText(find.byType(TextField), '');
        await tester.tap(find.widgetWithText(ChoiceChip, 'Artists'));
        await tester.pumpAndSettle();
        expect(find.text('Artist'), findsOneWidget);
        await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
        await tester.pumpAndSettle();
        expect(find.text('Quick Mix'), findsNothing);
        await tester.tap(find.byTooltip('Mix my library'));
        await settle();
        expect(handler.tracks, hasLength(50));
        expect(repo.reads, 2);
        expect(repo.scans, 1);
        expect(tester.takeException(), isNull);
      } finally {
        if (!repo.scan!.isCompleted) repo.scan!.complete();
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await handler.dispose();
          await store.db.close();
        });
      }
    },
  );
}
