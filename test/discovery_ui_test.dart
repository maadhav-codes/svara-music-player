import 'package:svara/features/discovery/ranked_discovery.dart';
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
  testWidgets(
    'YouTube discovery, debounce, pagination and uploader attribution',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Store store;
      await tester.runAsync(() async {
        store = await Store.open(path: inMemoryDatabasePath);
      });
      const channel = MethodChannel('test.discovery/youtube');
      final youtube = YouTubeRepository(store, channel: channel);
      var calls = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'cancel') return null;
        calls++;
        final later = (call.arguments as Map)['continuation'] != null;
        return {
          'tracks': [
            {
              'videoId': later ? 'bbbbbbbbbbb' : 'aaaaaaaaaaa',
              'title': later ? 'Second result' : 'First result',
              'uploader': 'Test channel',
            },
          ],
          'continuation': later ? null : 'next',
        };
      });
      Future<void> settle() async {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        });
        await tester.pumpAndSettle();
      }

      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              discoveryCatalogProvider.overrideWithValue(DiscoveryCatalog()),
              storeProvider.overrideWithValue(store),
              youtubeProvider.overrideWithValue(youtube),
            ],
            child: const MaterialApp(home: Scaffold(body: DiscoveryScreen())),
          ),
        );
        await settle();
        expect(find.byType(SegmentedButton), findsNothing);
        expect(calls, 0);
        await tester.enterText(find.byType(TextField), 'music');
        await tester.pump(const Duration(milliseconds: 200));
        expect(calls, 0);
        await tester.pump(const Duration(milliseconds: 200));
        await settle();
        expect(calls, 1);
        expect(find.byType(SegmentedButton<String>), findsOneWidget);
        expect(find.text('First result'), findsOneWidget);
        expect(find.textContaining('Test channel • YouTube'), findsOneWidget);
        await tester.ensureVisible(find.text('Load more'));
        await tester.tap(find.text('Load more'));
        await settle();
        expect(calls, 2);
        expect(find.text('Second result'), findsOneWidget);
        await tester.ensureVisible(find.byTooltip('Song options').first);
        await tester.tap(find.byTooltip('Song options').first);
        await tester.pumpAndSettle();
        expect(find.text('View Artist'), findsNothing);
        expect(find.text('Track Info'), findsOneWidget);
        Navigator.of(tester.element(find.text('Track Info'))).pop();
        await tester.pumpAndSettle();
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await tester.pumpAndSettle();
        expect(tester.takeException(), null);
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      } finally {
        await tester.pumpWidget(const SizedBox());
        messenger.setMockMethodCallHandler(channel, null);
        await tester.runAsync(() => store.db.close());
      }
    },
  );
}
