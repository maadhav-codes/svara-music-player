import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/providers.dart';
import 'package:svara/core/store.dart';
import 'package:svara/features/discovery/discovery_screen.dart';
import 'package:svara/features/discovery/youtube_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  testWidgets('YouTube categories, empty recovery and stale search rejection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late Store store;
    await tester.runAsync(() async {
      store = await Store.open(path: inMemoryDatabasePath);
    });
    const channel = MethodChannel('test.categories/youtube');
    final youtube = YouTubeRepository(store, channel: channel);
    final queries = <String>[];
    final rock = Completer<void>();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'cancel') return null;
      final query = (call.arguments as Map)['query'] as String;
      queries.add(query);
      if (query == 'rock music') await rock.future;
      return {
        'tracks': query == 'missing music'
            ? []
            : [
                {
                  'videoId': 'aaaaaaaaaaa',
                  'title': query,
                  'uploader': 'Test uploader',
                },
              ],
        'continuation': null,
      };
    });
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> choose(String name, {bool wait = true}) async {
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pump();
      final chip = find.widgetWithText(ChoiceChip, name);
      await tester.ensureVisible(chip);
      await tester.pump();
      await tester.tap(chip);
      if (wait) await settle();
    }

    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storeProvider.overrideWithValue(store),
            youtubeProvider.overrideWithValue(youtube),
          ],
          child: const MaterialApp(home: Scaffold(body: DiscoveryScreen())),
        ),
      );
      await settle();
      expect(queries.single, 'trending music today');
      expect(find.byType(ChoiceChip), findsNWidgets(6));
      expect(find.text('Suggested music search on YouTube'), findsOneWidget);
      await choose('Top Charts');
      expect(queries.last, 'top songs music charts');
      await choose('Chill / Lofi');
      expect(queries.last, 'chill lofi music');
      await choose('Workout');
      expect(queries.last, 'workout music');
      await choose('Rock', wait: false);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await choose('Pop');
      rock.complete();
      await settle();
      expect(find.text('pop music'), findsOneWidget);
      expect(find.text('rock music'), findsNothing);
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.pump(const Duration(milliseconds: 400));
      await settle();
      await tester.ensureVisible(find.text('Explore trending music'));
      expect(find.text('No songs found'), findsOneWidget);
      await tester.tap(find.text('Explore trending music'));
      await settle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.text('trending music today'), findsOneWidget);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    } finally {
      if (!rock.isCompleted) rock.complete();
      await tester.pumpWidget(const SizedBox());
      messenger.setMockMethodCallHandler(channel, null);
      await tester.runAsync(() => store.db.close());
    }
  });
}
