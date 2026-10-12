import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/providers.dart';
import 'package:svara/core/store.dart';
import 'package:svara/features/playlists/playlists_repository.dart';
import 'package:svara/features/playlists/playlists_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  for (final scenario in ['empty', 'nonempty', 'loading', 'error']) {
    testWidgets('playlist creation action: $scenario with pinned Favorites', (
      tester,
    ) async {
      late Store store;
      await tester.runAsync(() async {
        store = await Store.open(path: inMemoryDatabasePath);
      });
      final pending = Completer<List<Playlist>>();
      var discovered = false;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              storeProvider.overrideWithValue(store),
              playlistsProvider.overrideWith((ref) => pending.future),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: PlaylistsScreen(onDiscover: () => discovered = true),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Create playlist'), findsNothing);
        if (scenario == 'empty') pending.complete([]);
        if (scenario == 'nonempty') {
          pending.complete([const Playlist('p', 'Evening', [])]);
        }
        if (scenario == 'error') pending.completeError(Exception('failure'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        if (scenario == 'loading') {
          await tester.pump();
        } else {
          await tester.pumpAndSettle();
        }
        expect(find.text('Favorites'), findsOneWidget);
        expect(find.text('New playlist'), findsNothing);
        expect(
          find.text('Create playlist'),
          scenario == 'empty' || scenario == 'nonempty'
              ? findsOneWidget
              : findsNothing,
        );
        expect(
          find.text('Make a playlist of your own'),
          scenario == 'empty' ? findsOneWidget : findsNothing,
        );
        if (scenario == 'empty') {
          expect(find.text('Save songs you love'), findsOneWidget);
          expect(find.text('0 tracks'), findsNothing);
          await tester.tap(find.text('Discover music'));
          expect(discovered, isTrue);
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        } else {
          expect(find.text('Discover music'), findsNothing);
        }
        if (scenario == 'error') {
          expect(find.text('Retry playlists'), findsOneWidget);
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        if (!pending.isCompleted) pending.complete([]);
        await tester.runAsync(() => store.db.close());
      }
    });
  }
}
