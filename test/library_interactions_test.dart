import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/providers.dart';
import 'package:svara/core/store.dart';
import 'package:svara/core/track.dart';
import 'package:svara/features/library/library_screen.dart';
import 'package:svara/features/player/svara_handler.dart';
import 'package:svara/features/player/player_screen.dart';
import 'package:svara/features/playlists/playlists_repository.dart';
import 'package:svara/features/playlists/playlists_screen.dart';

import 'player_test.dart' show MemoryPlayer;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  const song = Track(
    id: '1',
    title: 'First light',
    artist: 'Artist',
    album: 'Morning',
    uri: 'content://music/1',
    durationMs: 180000,
  );
  const second = Track(
    id: '2',
    title: 'Evening',
    artist: 'Other artist',
    uri: 'content://music/2',
  );
  late Store store;
  late SvaraHandler handler;
  const channel = MethodChannel('app.svara/media');

  setUp(() async {
    store = await Store.open(path: inMemoryDatabasePath);
    handler = SvaraHandler(store, audioPlayer: MemoryPlayer());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'hasPermission') return true;
          if (call.method == 'scan') {
            return {
              'changed': [
                song.toJson(),
                second.toJson(),
                for (var i = 3; i < 30; i++)
                  Track(
                    id: '$i',
                    title: 'Song $i',
                    artist: 'Artist',
                    uri: 'content://music/$i',
                  ).toJson(),
              ],
              'ids': [for (var i = 1; i < 30; i++) '$i'],
            };
          }
          return null;
        });
  });
  tearDown(() async {
    await handler.dispose();
    await store.db.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  Future<void> settle(WidgetTester tester) async {
    // Provider invalidation starts follow-up database reads on the next frame.
    for (var i = 0; i < 3; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
    }
    await tester.pumpAndSettle();
  }

  Future<void> mount(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(store),
          handlerProvider.overrideWithValue(handler),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await settle(tester);
  }

  testWidgets(
    'full player adds the current song to new and existing playlists',
    (tester) async {
      await tester.runAsync(() async {
        await handler.restore();
        await handler.setQueue([song], start: false);
      });
      await mount(tester, const PlayerScreen());
      expect(
        tester.getCenter(find.byTooltip('Add to playlist')).dx,
        greaterThan(tester.getCenter(find.byTooltip('Favorite')).dx),
      );
      await tester.tap(find.byTooltip('Add to playlist'));
      await settle(tester);
      await tester.tap(find.text('New playlist'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Morning mix');
      await tester.tap(find.text('Save'));
      await settle(tester);
      final repo = PlaylistsRepository(store);
      var playlists = await tester.runAsync(repo.all);
      expect(playlists!.single.name, 'Morning mix');
      expect(playlists.single.tracks.single.id, song.id);
      expect(find.text('Saved to playlist'), findsOneWidget);

      await tester.runAsync(() => handler.setQueue([second], start: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add to playlist'));
      await settle(tester);
      await tester.tap(find.text('Morning mix'));
      await settle(tester);
      playlists = await tester.runAsync(repo.all);
      expect(playlists!.single.tracks.map((track) => track.id), [
        song.id,
        second.id,
      ]);

      await tester.tap(find.byTooltip('Add to playlist'));
      await settle(tester);
      await tester.tap(find.text('Morning mix'));
      await settle(tester);
      playlists = await tester.runAsync(repo.all);
      expect(playlists!.single.tracks.length, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'player heart saves a playable Favorites collection and removal updates heart',
    (tester) async {
      await tester.runAsync(() async {
        await handler.restore();
        await handler.setQueue([song], start: false);
      });
      await mount(tester, const PlayerScreen());
      await tester.tap(find.byTooltip('Favorite'));
      await settle(tester);
      expect(find.byTooltip('Remove favorite'), findsOneWidget);
      expect(find.text('Added to Favorites in Playlists'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove favorite'));
      await settle(tester);
      expect(find.text('Removed from Favorites'), findsOneWidget);
      expect(find.text('Added to Favorites in Playlists'), findsNothing);
      await tester.tap(find.byTooltip('Favorite'));
      await settle(tester);
      expect(find.text('Added to Favorites in Playlists'), findsOneWidget);

      final context = tester.element(find.byType(PlayerScreen));
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Playlists')),
            body: const PlaylistsScreen(),
          ),
        ),
      );
      await settle(tester);
      expect(find.text('Favorites'), findsOneWidget);
      expect(find.text('1 track • Saved with the heart'), findsOneWidget);
      await tester.tap(find.text('Favorites'));
      await settle(tester);
      expect(find.text('First light'), findsOneWidget);
      await tester.tap(find.text('Play favorites'));
      await settle(tester);
      expect(handler.tracks.single.id, song.id);
      expect(handler.player.playing, isTrue);

      await tester.tap(find.byTooltip('Song options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from Favorites'));
      await settle(tester);
      await settle(tester);
      expect(find.text('Your favorites start with a heart'), findsOneWidget);
      expect(
        (await tester.runAsync(() => PlaylistsRepository(store).favorites()))!
            .tracks,
        isEmpty,
      );
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      expect(find.text('0 tracks • Saved with the heart'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      expect(find.byTooltip('Favorite'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'chips filter in one tap, stay pinned and offer Discover for empty search',
    (tester) async {
      var discovered = false;
      await mount(tester, LibraryScreen(onDiscover: () => discovered = true));
      expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Artists'));
      await settle(tester);
      expect(find.text('Other artist'), findsOneWidget);
      await tester.tap(find.text('Other artist'));
      await tester.pumpAndSettle();
      expect(find.text('Evening'), findsOneWidget);
      expect(find.text('First light'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await settle(tester);
      expect(find.text('First light'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -380));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(ChoiceChip, 'All').hitTestable(),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.widgetWithText(ChoiceChip, 'All')).dy,
        lessThan(80),
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'missing song');
      await settle(tester);
      await tester.ensureVisible(find.text('Explore Discover'));
      await tester.pumpAndSettle();
      expect(find.text('No songs found'), findsOneWidget);
      await tester.tap(find.text('Explore Discover'));
      expect(discovered, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'shared menu favorites, queue insertion, details and playlist creation work',
    (tester) async {
      await tester.runAsync(
        () => handler.setQueue(
          [second, song],
          start: false,
          position: const Duration(seconds: 12),
        ),
      );
      await mount(tester, SongTile(song, onPlay: () {}));
      Future<void> choose(String action) async {
        await tester.tap(find.byTooltip('Song options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(action));
        await settle(tester);
      }

      await choose('Favorite');
      await tester.tap(find.byTooltip('Song options'));
      await tester.pumpAndSettle();
      expect(find.text('Unfavorite'), findsOneWidget);
      await tester.tap(find.text('Unfavorite'));
      await settle(tester);
      expect(
        (await tester.runAsync(() => PlaylistsRepository(store).favorites()))!
            .tracks,
        isEmpty,
      );
      await choose('Play Next');
      expect(handler.tracks.map((t) => t.id), ['2', '1', '1']);
      expect(handler.activeIndex, 0);
      expect(handler.position, const Duration(seconds: 12));
      expect(handler.player.playing, isFalse);
      await choose('Add to Queue');
      expect(handler.tracks.length, 4);
      await choose('Track Info / File Details');
      expect(find.text('3:00'), findsOneWidget);
      expect(find.text('content://music/1'), findsOneWidget);
      Navigator.of(tester.element(find.text('Track Info'))).pop();
      await tester.pumpAndSettle();
      await choose('Add to Playlist');
      await tester.tap(find.text('New playlist'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Morning mix');
      await tester.tap(find.text('Save'));
      await settle(tester);
      final playlists = await tester.runAsync(
        () => PlaylistsRepository(store).all(),
      );
      expect(playlists!.single.tracks.single.id, song.id);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets('empty playlist action returns to Library', (tester) async {
    var libraryOpened = false;
    await mount(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => PlaylistDetail(
                Playlist('empty', 'Empty mix', []),
                onLibrary: () => libraryOpened = true,
              ),
            ),
          ),
          child: const Text('Open playlist'),
        ),
      ),
    );
    await tester.tap(find.text('Open playlist'));
    await tester.pumpAndSettle();
    expect(find.text('Every playlist starts with a song'), findsOneWidget);
    await tester.tap(find.text('Browse Library'));
    await tester.pumpAndSettle();
    expect(libraryOpened, isTrue);
    expect(find.text('Open playlist'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
