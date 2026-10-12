import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/providers.dart';
import 'package:svara/core/store.dart';
import 'package:svara/features/settings/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

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
