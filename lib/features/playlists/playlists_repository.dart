import '../../core/store.dart';
import '../../core/track.dart';

class Playlist {
  const Playlist(this.id, this.name, this.tracks);
  final String id, name;
  final List<Track> tracks;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'tracks': tracks.map((t) => t.toSavedJson()).toList(),
  };
  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
    j['id'] as String,
    j['name'] as String,
    (j['tracks'] as List)
        .map((t) => Track.fromJson(Map<String, dynamic>.from(t as Map)))
        .toList(),
  );
}

class PlaylistsRepository {
  PlaylistsRepository(this.store);
  final Store store;
  Future<List<Playlist>> all() async =>
      ((await store.read('playlists') as List?) ?? [])
          .map((j) => Playlist.fromJson(Map<String, dynamic>.from(j as Map)))
          .toList();
  Future<void> save(List<Playlist> playlists) =>
      store.write('playlists', playlists.map((p) => p.toJson()).toList());
}
