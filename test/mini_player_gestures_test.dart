import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/providers.dart';
import 'package:svara/core/store.dart';
import 'package:svara/core/track.dart';
import 'package:svara/features/player/player_screen.dart';
import 'package:svara/features/player/svara_handler.dart';

import 'player_test.dart' show MemoryPlayer;

class GestureHandler extends SvaraHandler {
  GestureHandler(super.store, {required super.audioPlayer});
  int nextCalls = 0, previousCalls = 0, playCalls = 0, selected = 0;
  @override
  int get activeIndex => selected;
  @override
  Future<void> skipToNext() async {
    nextCalls++;
    if (selected < 2) selected++;
  }

  @override
  Future<void> skipToPrevious() async {
    previousCalls++;
    if (selected > 0) selected--;
  }

  @override
  Future<void> play() async {
    playCalls++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  testWidgets(
    'mini gestures resist drag, respect reduced motion, click on changes and dismiss player safely',
    (tester) async {
      final haptics = <Object?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              haptics.add(call.arguments);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      late Store store;
      late GestureHandler handler;
      await tester.runAsync(() async {
        store = await Store.open(path: inMemoryDatabasePath);
        handler = GestureHandler(store, audioPlayer: MemoryPlayer());
        await handler.setQueue(
          List.generate(
            3,
            (index) => Track(
              id: 'youtube:gesture$index',
              title: 'Song $index',
              artist: 'Test artist',
              uri: 'https://example.com/$index',
              durationMs: 180000,
            ),
          ),
          start: false,
        );
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storeProvider.overrideWithValue(store),
            handlerProvider.overrideWithValue(handler),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox.expand(),
              bottomNavigationBar: SizedBox(height: 72, child: MiniPlayer()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> swipe(Offset offset) async {
        await tester.drag(find.byType(MiniPlayer), offset);
        await tester.pumpAndSettle();
      }

      final title = find.text('Song 0');
      final originalX = tester.getTopLeft(title).dx;
      final drag = await tester.startGesture(
        tester.getCenter(find.byType(MiniPlayer)),
      );
      await drag.moveBy(const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(title).dx, closeTo(originalX - 20, .1));
      await drag.up();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(title).dx, closeTo(originalX, .1));
      expect(haptics, ['HapticFeedbackType.selectionClick']);
      expect(handler.nextCalls, 1);
      expect(find.byType(PlayerScreen), findsNothing);
      await swipe(const Offset(100, 0));
      expect(handler.previousCalls, 1);
      await swipe(const Offset(-100, -25));
      expect(handler.nextCalls, 2);
      expect(find.byType(PlayerScreen), findsNothing);
      await swipe(const Offset(-25, 0));
      await swipe(const Offset(0, 100));
      expect(handler.nextCalls, 2);
      expect(handler.previousCalls, 1);
      expect(haptics.length, 3);
      expect(find.byType(PlayerScreen), findsNothing);
      await swipe(const Offset(0, -120));
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(handler.nextCalls, 2);
      expect(handler.previousCalls, 1);
      await tester.drag(find.byType(ClipOval).first, const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsOneWidget);
      // Force metadata to scroll to exercise dismissal away from its top.
      tester.view.physicalSize = const Size(800, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      scroll.position.jumpTo(scroll.position.maxScrollExtent.clamp(1, 100));
      await tester.pumpAndSettle();
      await tester.fling(
        find.byType(SingleChildScrollView),
        const Offset(0, 120),
        700,
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsOneWidget);
      scroll.position.jumpTo(0);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.pumpAndSettle();
      final cancelledClose = await tester.startGesture(
        tester.getCenter(find.byType(ClipOval).first),
      );
      await cancelledClose.moveBy(const Offset(0, 120));
      await cancelledClose.cancel();
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsOneWidget);
      await tester.fling(
        find.byType(ClipOval).first,
        const Offset(0, 120),
        700,
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsNothing);
      await tester.tap(find.byType(MiniPlayer));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Close player'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next track'));
      await tester.pumpAndSettle();
      expect(handler.nextCalls, 3);
      expect(find.byType(PlayerScreen), findsNothing);
      await tester.tap(find.byTooltip('Play'));
      await tester.pumpAndSettle();
      expect(handler.playCalls, 1);
      expect(handler.nextCalls, 3);
      await tester.fling(find.byType(MiniPlayer), const Offset(-65, 0), 1000);
      await tester.pumpAndSettle();
      expect(handler.nextCalls, 4);
      final cancelled = await tester.startGesture(
        tester.getCenter(find.byType(MiniPlayer)),
      );
      await cancelled.moveBy(const Offset(100, 0));
      await cancelled.cancel();
      await tester.pumpAndSettle();
      expect(handler.previousCalls, 1);
      expect(
        haptics.length,
        3,
      ); // Buttons, boundaries and cancelled drags do not buzz.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await tester.pumpAndSettle();
      final reducedX = tester.getTopLeft(title).dx;
      final reducedDrag = await tester.startGesture(
        tester.getCenter(find.byType(MiniPlayer)),
      );
      await reducedDrag.moveBy(const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(title).dx, reducedX);
      await reducedDrag.cancel();
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await handler.dispose();
        await store.db.close();
      });
    },
  );
}
