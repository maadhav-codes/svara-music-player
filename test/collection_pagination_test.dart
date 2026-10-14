import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/providers.dart';
import 'package:svara/core/store.dart';
import 'package:svara/features/discovery/artist.dart';
import 'package:svara/features/discovery/artist_screen.dart';
import 'package:svara/features/discovery/youtube_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  for (final emptyPage in [true, false]) {
    testWidgets(
      'collection stops on ${emptyPage ? 'empty page' : 'repeated cursor'}',
      (tester) async {
        late Store store;
        await tester.runAsync(() async {
          store = await Store.open(path: inMemoryDatabasePath);
        });
        const channel = MethodChannel('test.collection/pagination');
        final requested = <String?>[];
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'cancel') return null;
          final cursor = (call.arguments as Map)['continuation'] as String?;
          requested.add(cursor);
          return {
            'tracks': cursor != null && emptyPage
                ? []
                : [
                    {
                      'videoId': cursor == null ? 'aaaaaaaaaaa' : 'bbbbbbbbbbb',
                      'title': 'Track ${requested.length}',
                      'uploader': 'Artist',
                    },
                  ],
            // A broken API must not cause an infinite request loop.
            'continuation': 'next',
          };
        });
        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                youtubeProvider.overrideWithValue(
                  YouTubeRepository(store, channel: channel),
                ),
              ],
              child: MaterialApp(
                home: CollectionScreen(
                  MusicCollection.fromJson({
                    'url': 'https://www.youtube.com/playlist?list=PLtest',
                    'name': 'Collection',
                    'artist': 'Artist',
                  }),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(requested, [null, 'next']);
          expect(find.text('End of list'), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.text('Track 1'), findsOneWidget);
          expect(
            find.text('Track 2'),
            emptyPage ? findsNothing : findsOneWidget,
          );
          expect(find.text('Load more'), findsNothing);
        } finally {
          await tester.pumpWidget(const SizedBox());
          messenger.setMockMethodCallHandler(channel, null);
          await tester.runAsync(() => store.db.close());
        }
      },
    );
  }
}
