import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'artist.dart';

final followedArtistsProvider =
    AsyncNotifierProvider<FollowedArtists, List<Artist>>(FollowedArtists.new);

class FollowedArtists extends AsyncNotifier<List<Artist>> {
  Future<void> _pending = Future<void>.value();
  @override
  Future<List<Artist>> build() async {
    final saved =
        await ref.watch(storeProvider).read('followedArtists') as List? ?? [];
    return saved
        .map((j) => Artist.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
  }

  Future<void> toggle(Artist artist) {
    final task = _pending.then((_) async {
      final artists = List<Artist>.of(await future);
      if (artists.any((a) => a.id == artist.id)) {
        artists.removeWhere((a) => a.id == artist.id);
      } else {
        artists.add(artist);
      }
      await ref
          .read(storeProvider)
          .write('followedArtists', artists.map((a) => a.toJson()).toList());
      state = AsyncData(artists);
    });
    _pending = task.catchError((Object _) {});
    return task;
  }
}
