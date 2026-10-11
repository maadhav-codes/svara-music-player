import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/providers.dart';
import 'package:svara/core/store.dart';
import 'package:svara/core/track.dart';
import 'package:svara/features/playlists/favorites_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  late Store store;
  late ProviderContainer container;
  const local = Track(
    id: 'local:external:1',
    title: 'Local song',
    artist: 'Artist',
    uri: 'content://media/external/audio/media/1',
  );
  const youtube = Track(
    id: 'youtube:aaaaaaaaaaa',
    title: 'Online song',
    artist: 'Uploader',
    uri: 'https://googlevideo.com/secret-signed-stream',
    artwork: 'https://example.org/art.jpg',
  );
  const audius = Track(
    id: 'audius:abc',
    title: 'Audius original title',
    artist: 'Audius artist',
    uri: 'https://example.org/private-stream',
  );

  setUp(() async {
    store = await Store.open(path: inMemoryDatabasePath);
    container = ProviderContainer(
      overrides: [storeProvider.overrideWithValue(store)],
    );
  });
  tearDown(() async {
    container.dispose();
    await store.db.close();
  });

  test(
    'mixed favorites survive controller recreation without signed URLs',
    () async {
      final controller = container.read(favoritesProvider.notifier);
      await controller.toggle(local);
      await controller.toggle(youtube);
      await controller.toggle(audius);
      container.dispose();
      container = ProviderContainer(
        overrides: [storeProvider.overrideWithValue(store)],
      );
      await container.read(favoritesProvider.notifier).load();
      expect(container.read(favoritesProvider), {
        local.id,
        youtube.id,
        audius.id,
      });
      final tracks = await container.read(favoriteTracksProvider.future);
      expect(tracks.map((track) => track.id), [
        audius.id,
        youtube.id,
        local.id,
      ]);
      expect(tracks[1].title, youtube.title);
      expect(tracks[1].uri, 'https://www.youtube.com/watch?v=aaaaaaaaaaa');
      expect(tracks.first.title, 'Audius track');
      final saved = jsonEncode(await store.read('favoriteTracks'));
      expect(saved, isNot(contains('secret-signed-stream')));
      expect(saved, isNot(contains('private-stream')));
      expect(saved, isNot(contains('art.jpg')));
      await container.read(favoritesProvider.notifier).toggle(youtube);
      expect(container.read(favoritesProvider), {local.id, audius.id});
      expect(
        (await container.read(favoriteTracksProvider.future))
            .map((track) => track.id),
        [audius.id, local.id],
      );
    },
  );

  test(
    'legacy IDs recover local tracks across pages and online references',
    () async {
      final locals = [
        for (var i = 0; i < 205; i++)
          Track(
            id: 'local:$i',
            title: 'Song $i',
            artist: 'Artist',
            uri: 'content://music/$i',
          ),
      ];
      await store.reconcile(locals, locals.map((track) => track.id).toSet());
      await store.write('favorites', [
        'local:99',
        youtube.id,
        audius.id,
        'local:missing',
      ]);
      await store.write('playback', {
        'tracks': [youtube.toSavedJson()],
      });
      final tracks = await FavoritesRepository(store).tracks();
      expect(tracks.map((track) => track.id), [
        'local:99',
        youtube.id,
        audius.id,
      ]);
      expect(tracks.first.title, 'Song 99');
      expect(tracks[1].title, youtube.title);
      expect(tracks.last.providerId, 'abc');
    },
  );

  test(
    'startup load and rapid heart taps cannot lose or duplicate favorites',
    () async {
      final controller = container.read(favoritesProvider.notifier);
      await Future.wait([
        controller.load(),
        controller.toggle(local),
        controller.toggle(youtube),
        controller.toggle(local),
      ]);
      expect(container.read(favoritesProvider), {youtube.id});
      expect(await store.read('favorites'), [youtube.id]);
      final tracks = await FavoritesRepository(store).tracks();
      expect(tracks.single.id, youtube.id);
      expect((await store.read('favoriteTracks') as List).length, 1);
    },
  );
  test(
    'a failed reference write rolls back the favorite ID and heart state',
    () async {
      await store.db.execute('''
      CREATE TRIGGER fail_favorite_reference BEFORE INSERT ON settings
      WHEN NEW.key = 'favoriteTracks'
      BEGIN SELECT RAISE(ABORT, 'test write failure'); END
    ''');
      final controller = container.read(favoritesProvider.notifier);
      await expectLater(
        controller.toggle(local),
        throwsA(isA<DatabaseException>()),
      );
      expect(container.read(favoritesProvider), isEmpty);
      expect(await store.read('favorites'), isNull);
      expect(await store.read('favoriteTracks'), isNull);
      await store.db.execute('DROP TRIGGER fail_favorite_reference');
      await controller.toggle(local);
      expect(container.read(favoritesProvider), {local.id});
    },
  );
}
