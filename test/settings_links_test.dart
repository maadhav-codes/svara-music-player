import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/providers.dart';
import 'package:svara/core/store.dart';
import 'package:svara/features/settings/settings_screen.dart';
import 'package:svara/core/media_source.dart';
import 'package:svara/features/discovery/youtube_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  testWidgets('quality stays available with legacy YouTube disable setting', (
    tester,
  ) async {
    late Store store;
    late YouTubeRepository youtube;
    await tester.runAsync(() async {
      store = await Store.open(path: inMemoryDatabasePath);
      await store.write('youtubeEnabled', false);
      youtube = YouTubeRepository(store);
      await youtube.loadSettings();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(store),
          youtubeProvider.overrideWithValue(youtube),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('YouTube discovery'), findsNothing);
    await tester.tap(find.text('Standard (128 kbps)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('High (256 kbps)').last);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      expect(await store.read('streamQuality'), 'high');
      expect(youtube.quality, StreamQuality.high);
    });
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => store.db.close());
  });

  for (final unavailable in [false, true]) {
    testWidgets('Developer opens email; unavailable=$unavailable', (
      tester,
    ) async {
      late Store store;
      await tester.runAsync(() async {
        store = await Store.open(path: inMemoryDatabasePath);
      });
      const channel = MethodChannel('app.svara/media');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (unavailable) {
          throw PlatformException(code: 'launcher');
        }
        return null;
      });
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        await store.db.close();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [storeProvider.overrideWithValue(store)],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.scrollUntilVisible(find.text('Developer'), 250);
      await tester.tap(find.text('Developer'));
      await tester.pumpAndSettle();

      expect(calls.single.method, 'openUrl');
      expect(calls.single.arguments, {
        'url': 'mailto:mayurdayal.engineer@gmail.com',
      });
      expect(
        find.text(
          'Could not open an email app. Contact mayurdayal.engineer@gmail.com.',
        ),
        unavailable ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
