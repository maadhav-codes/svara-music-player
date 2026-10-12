import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/providers.dart';
import 'package:svara/core/store.dart';
import 'package:svara/features/discovery/discovery_screen.dart';
import 'package:svara/features/discovery/discovery_category.dart';
import 'package:svara/features/discovery/ranked_discovery.dart';
import 'package:svara/features/discovery/youtube_repository.dart';

class TestCatalog extends DiscoveryCatalog {
  TestCatalog() : super(endpoint: 'https://example.test');
  bool fail = false;
  final requests = <String>[];
  @override
  Future<BrowseCapabilities> capabilities({CancelToken? cancel}) async =>
      const BrowseCapabilities(
        {'in': 'India', 'us': 'United States'},
        [DiscoveryCategory('rock', 'Rock'), DiscoveryCategory('pop', 'Pop')],
      );
  @override
  Future<RankedPage> page({
    required String market,
    String? genre,
    String scope = 'week',
    String? cursor,
    CancelToken? cancel,
  }) async {
    requests.add('$market:$genre');
    if (fail) throw Exception('outage');
    return RankedPage(
      entries: const [],
      sourceName: 'Test catalog',
      market: market,
      scope: scope,
      genre: genre,
      fetchedAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }
}

class CommunityCatalog extends TestCatalog {
  final periods = <String>[];
  @override
  Future<BrowseCapabilities> capabilities({CancelToken? cancel}) async =>
      const BrowseCapabilities(
        {'global': 'ListenBrainz community'},
        [],
        scopes: {'week': 'Weekly', 'month': 'Monthly', 'year': 'Yearly'},
        browseTitle: 'Popular on ListenBrainz',
      );
  @override
  Future<RankedPage> page({
    required String market,
    String? genre,
    String scope = 'week',
    String? cursor,
    CancelToken? cancel,
  }) {
    periods.add(scope);
    return super.page(
      market: market,
      genre: genre,
      scope: scope,
      cursor: cursor,
      cancel: cancel,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  testWidgets(
    'Browse context, visible modes, failures and stale search rejection',
    (tester) async {
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
      final catalog = TestCatalog();
      final queries = <String>[];
      final old = Completer<void>();
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'cancel') return null;
        final query = (call.arguments as Map)['query'] as String;
        queries.add(query);
        if (query == 'old music') await old.future;
        return {
          'tracks': [
            {
              'videoId': 'aaaaaaaaaaa',
              'title': query,
              'uploader': 'Test uploader',
            },
          ],
          'artists': [],
          'continuation': null,
        };
      });
      Future<void> settle() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pumpAndSettle();
      }

      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              storeProvider.overrideWithValue(store),
              youtubeProvider.overrideWithValue(youtube),
              discoveryCatalogProvider.overrideWithValue(catalog),
            ],
            child: const MaterialApp(home: Scaffold(body: DiscoveryScreen())),
          ),
        );
        await settle();
        expect(queries, isEmpty);
        expect(find.text('Popular in India'), findsOneWidget);
        expect(find.byType(SegmentedButton<String>), findsNothing);
        await tester.tap(find.text('Rock'));
        await settle();
        expect(catalog.requests.last, 'in:rock');
        await tester.enterText(find.byType(TextField), 'old');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        expect(find.byType(SegmentedButton<String>), findsOneWidget);
        expect(find.text('Browse genres'), findsNothing);
        expect(find.textContaining('Browse preferences'), findsNothing);
        await tester.enterText(find.byType(TextField), 'new');
        await tester.pump(const Duration(milliseconds: 400));
        await settle();
        old.complete();
        await settle();
        expect(find.text('new music'), findsOneWidget);
        expect(find.text('old music'), findsNothing);
        await tester.tap(find.text('Artists'));
        await settle();
        expect(queries.last, 'new');
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'new',
        );
        await tester.tap(find.byTooltip('Clear search'));
        await settle();
        expect(find.text('Rock · India'), findsOneWidget);
        expect(catalog.requests.last, 'in:rock');
        await tester.tap(
          find
              .byWidgetPredicate(
                (widget) =>
                    widget is Tooltip &&
                    (widget.message?.startsWith('Browse preferences') ?? false),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('United States').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply'));
        await settle();
        expect(catalog.requests.last, 'us:rock');
        catalog.fail = true;
        await tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh();
        await settle();
        expect(find.text('Retry'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'direct');
        await tester.pump(const Duration(milliseconds: 400));
        await settle();
        expect(find.text('direct music'), findsOneWidget);
        expect(
          queries.any((q) => q.contains('trending') || q.contains('charts')),
          false,
        );
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        for (final size in [const Size(320, 568), const Size(568, 320)]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      } finally {
        if (!old.isCompleted) old.complete();
        await tester.pumpWidget(const SizedBox());
        catalog.dispose();
        messenger.setMockMethodCallHandler(channel, null);
        await tester.runAsync(() => store.db.close());
      }
    },
  );
  testWidgets(
    'community preferences offer periods, hide countries and survive direct search',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Store store;
      await tester.runAsync(() async {
        store = await Store.open(path: inMemoryDatabasePath);
      });
      final catalog = CommunityCatalog();
      const channel = MethodChannel('test.community/youtube');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'tracks': [], 'continuation': null},
      );
      Future<void> settle() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pumpAndSettle();
      }

      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              storeProvider.overrideWithValue(store),
              discoveryCatalogProvider.overrideWithValue(catalog),
              youtubeProvider.overrideWithValue(
                YouTubeRepository(store, channel: channel),
              ),
            ],
            child: const MaterialApp(home: Scaffold(body: DiscoveryScreen())),
          ),
        );
        await settle();
        expect(find.text('Popular on ListenBrainz'), findsOneWidget);
        expect(find.text('Browse genres'), findsNothing);
        await tester.tap(
          find
              .byWidgetPredicate(
                (widget) =>
                    widget is Tooltip &&
                    (widget.message?.startsWith('Browse preferences') ?? false),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Chart market'), findsNothing);
        expect(find.text('Reporting period'), findsOneWidget);
        expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Monthly').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply'));
        await settle();
        expect(catalog.periods.last, 'month');
        expect(find.byTooltip('Browse preferences · Monthly'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'quiet');
        await tester.pump(const Duration(milliseconds: 400));
        await settle();
        expect(find.byTooltip('Browse preferences · Monthly'), findsNothing);
        await tester.tap(find.byTooltip('Clear search'));
        await settle();
        expect(catalog.periods.last, 'month');
        await tester.tap(find.byTooltip('Browse preferences · Monthly'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reset'));
        await tester.pumpAndSettle();
        expect(find.text('Weekly'), findsOneWidget);
        await tester.tap(find.text('Apply'));
        await settle();
        expect(catalog.periods.last, 'week');
      } finally {
        await tester.pumpWidget(const SizedBox());
        catalog.dispose();
        messenger.setMockMethodCallHandler(channel, null);
        await tester.runAsync(() => store.db.close());
      }
    },
  );
}
