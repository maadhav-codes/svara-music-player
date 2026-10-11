import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/providers.dart';
import 'package:svara/core/store.dart';
import 'package:svara/features/discovery/audius_repository.dart';
import 'package:svara/features/discovery/discovery_screen.dart';
import 'package:svara/features/discovery/youtube_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  test('Audius categories keep genre, range and page caches separate from text search', () async {
    final store = await Store.open(path: inMemoryDatabasePath);
    final requests = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.org'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {'data': []},
            ),
          );
        },
      ),
    );
    final repo = AudiusRepository(store, client: dio);
    try {
      await repo.tracks(genre: 'Pop', time: 'week');
      await repo.tracks(genre: 'Pop', time: 'week');
      expect(requests.length, 1);
      await repo.tracks(genre: 'Rock', time: 'week');
      await repo.tracks(genre: 'Rock', time: 'month', offset: 30);
      expect(requests.length, 3);
      expect(requests.last.path, '/v1/tracks/trending');
      expect(requests.last.queryParameters, containsPair('genre', 'Rock'));
      expect(requests.last.queryParameters, containsPair('time', 'month'));
      expect(requests.last.queryParameters, containsPair('offset', 30));
      await repo.tracks(query: 'workout', genre: 'Pop', time: 'month');
      expect(requests.last.path, '/v1/tracks/search');
      expect(requests.last.queryParameters, containsPair('query', 'workout'));
      expect(requests.last.queryParameters.containsKey('genre'), false);
      expect(requests.last.queryParameters.containsKey('time'), false);
    } finally {
      dio.close();
      await store.db.close();
    }
  });

  testWidgets(
    'discovery chips select feeds, paginate, switch providers and reject stale results',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Store store;
      await tester.runAsync(() async {
        store = await Store.open(path: inMemoryDatabasePath);
      });
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://example.org'));
      final rock = Completer<void>();
      var delayRock = false;
      var failNext = false;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            requests.add(options);
            if (failNext) {
              failNext = false;
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(requestOptions: options, statusCode: 403),
                  type: DioExceptionType.badResponse,
                ),
              );
              return;
            }
            final genre = options.queryParameters['genre'];
            if (delayRock && genre == 'Rock') await rock.future;
            final name =
                genre ??
                options.queryParameters['query'] ??
                options.queryParameters['time'];
            final offset = options.queryParameters['offset'] as int;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data': List.generate(
                    30,
                    (i) => {
                      'id': '$name-${offset + i}',
                      'title': '$name discovery ${offset + i}',
                      'user': {'name': 'Test creator'},
                    },
                  ),
                },
              ),
            );
          },
        ),
      );
      const channel = MethodChannel('test.categories/youtube');
      final youtube = YouTubeRepository(store, channel: channel);
      final queries = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'cancel') return null;
            queries.add((call.arguments as Map)['query'] as String);
            return {
              'tracks': [
                {
                  'videoId': 'aaaaaaaaaaa',
                  'title': 'Suggested video',
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

      Future<void> top() async {
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pump();
      }

      Future<void> choose(String name) async {
        await top();
        final chip = find.widgetWithText(ChoiceChip, name);
        await tester.ensureVisible(
          find.byKey(const ValueKey('discovery-categories')),
        );
        await tester.pump();
        await tester.ensureVisible(chip);
        await tester.pump();
        await tester.tap(chip);
        await settle();
      }

      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              storeProvider.overrideWithValue(store),
              audiusProvider.overrideWithValue(
                AudiusRepository(store, client: dio),
              ),
              youtubeProvider.overrideWithValue(youtube),
            ],
            child: const MaterialApp(home: Scaffold(body: DiscoveryScreen())),
          ),
        );
        await settle();
        expect(find.byType(ChoiceChip), findsNWidgets(6));
        expect(
          tester
              .widget<ChoiceChip>(
                find.widgetWithText(ChoiceChip, 'Trending Today'),
              )
              .selected,
          true,
        );
        final categoryRow = tester.widget<SingleChildScrollView>(
          find.byKey(const ValueKey('discovery-categories')),
        );
        expect(categoryRow.scrollDirection, Axis.horizontal);
        final firstY = tester
            .getTopLeft(find.widgetWithText(ChoiceChip, 'Trending Today'))
            .dy;
        expect(
          tester.getTopLeft(find.widgetWithText(ChoiceChip, 'Rock')).dy,
          firstY,
        );
        expect(find.text('Audius trending · past week'), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.text('Audius trending · past week'))
              .style!
              .fontSize,
          lessThan(
            tester
                .widget<Text>(find.text('Trending Today').last)
                .style!
                .fontSize!,
          ),
        );
        expect(requests.single.queryParameters['time'], 'week');
        await choose('Trending Today');
        expect(
          tester
              .widget<ChoiceChip>(
                find.widgetWithText(ChoiceChip, 'Trending Today'),
              )
              .selected,
          true,
        );
        expect(find.text('Audius trending · past week'), findsOneWidget);
        await choose('Top Charts');
        expect(requests.last.queryParameters['time'], 'month');
        await tester.scrollUntilVisible(
          find.text('Load more'),
          700,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Load more'));
        await settle();
        expect(requests.last.queryParameters['offset'], 30);
        expect(requests.last.queryParameters['time'], 'month');
        await choose('Chill / Lofi');
        expect(requests.last.queryParameters['genre'], 'Lo-Fi');
        await choose('Workout');
        expect(requests.last.queryParameters['query'], 'workout');
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          '',
        );
        store.clearSessionCache();
        failNext = true;
        await choose('Pop');
        expect(
          find.textContaining('Audius access is restricted'),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Retry'));
        await tester.tap(find.text('Retry'));
        await settle();
        expect(find.text('Pop discovery 0'), findsOneWidget);
        expect(requests.last.queryParameters['genre'], 'Pop');
        await choose('Workout');
        await top();
        await tester.tap(find.text('YouTube'));
        await settle();
        expect(queries.last, 'workout music');
        expect(find.text('Suggested music search on YouTube'), findsOneWidget);
        await choose('Pop');
        expect(queries.last, 'pop music');
        await top();
        await tester.enterText(find.byType(TextField), 'custom');
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(ChoiceChip), findsNothing);
        expect(queries.last, 'pop music');
        await tester.pump(const Duration(milliseconds: 200));
        await settle();
        expect(queries.last, 'custom music');
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'custom',
        );
        await tester.enterText(find.byType(TextField), '');
        await tester.pump(const Duration(milliseconds: 400));
        await settle();
        expect(find.byType(ChoiceChip), findsNWidgets(6));
        expect(
          queries.last,
          'custom music',
        ); // Empty YouTube browse does not run a hidden search.
        await tester.tap(find.text('Audius'));
        await settle();
        delayRock = true;
        await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Rock'));
        await tester.tap(find.widgetWithText(ChoiceChip, 'Rock'));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Pop'));
        await tester.tap(find.widgetWithText(ChoiceChip, 'Pop'));
        await settle();
        rock.complete();
        await settle();
        expect(find.text('Pop discovery 0'), findsOneWidget);
        expect(find.text('Rock discovery 0'), findsNothing);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await tester.pumpAndSettle();
        expect(tester.takeException(), null);
        await choose('Rock');
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Rock'))
              .selected,
          true,
        );
        expect(
          find.text('Rock trending on Audius · past week'),
          findsOneWidget,
        );
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      } finally {
        if (!rock.isCompleted) rock.complete();
        await tester.pumpWidget(const SizedBox());
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        dio.close(force: true);
        await tester.runAsync(() => store.db.close());
      }
    },
  );
}
