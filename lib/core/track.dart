class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.uri,
    this.album = '',
    this.folder = '',
    this.durationMs = 0,
    this.artwork,
    this.artistId,
    this.online = false,
    this.streamable = true,
    this.modified = 0,
  });
  final String id, title, artist, uri, album, folder;
  final String? artwork, artistId;
  final int durationMs, modified;
  final bool online, streamable;
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'uri': uri,
    'album': album,
    'folder': folder,
    'durationMs': durationMs,
    'artwork': artwork,
    'artistId': artistId,
    'online': online,
    'streamable': streamable,
    'modified': modified,
  };
  // Saved Audius selections contain a reference, never cached provider metadata.
  Map<String, Object?> toSavedJson() => online
      ? {
          'id': id,
          'title': 'Audius track',
          'artist': 'Audius',
          'uri': uri,
          'online': true,
          'streamable': true,
        }
      : toJson();
  factory Track.fromJson(Map<String, dynamic> j) => Track(
    id: j['id'] as String,
    title: j['title'] as String,
    artist: j['artist'] as String,
    uri: j['uri'] as String,
    album: j['album'] as String? ?? '',
    folder: j['folder'] as String? ?? '',
    durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
    modified: (j['modified'] as num?)?.toInt() ?? 0,
    artwork: j['artwork'] as String?,
    artistId: j['artistId'] as String?,
    online: j['online'] == true,
    streamable: j['streamable'] != false,
  );
}

List<Track> quickMix(
  List<Track> tracks,
  Set<String> favorites,
  Map<String, int> history, {
  int limit = 50,
}) {
  final local = tracks.where((t) => !t.online).toList();
  local.sort((a, b) {
    final fav =
        (favorites.contains(b.id) ? 1 : 0) - (favorites.contains(a.id) ? 1 : 0);
    if (fav != 0) return fav;
    final age = (history[a.id] ?? 0).compareTo(history[b.id] ?? 0);
    return age != 0 ? age : a.id.compareTo(b.id);
  });
  // Interleave favorites with other least-recently-played songs.
  final liked = local.where((t) => favorites.contains(t.id)).toList();
  final other = local.where((t) => !favorites.contains(t.id)).toList();
  final mix = <Track>[];
  for (var i = 0; i < local.length && mix.length < limit; i++) {
    if (i < liked.length) mix.add(liked[i]);
    if (i < other.length && mix.length < limit) mix.add(other[i]);
  }
  return mix;
}

List<T> moveQueueItem<T>(List<T> items, int oldIndex, int newIndex) {
  final copy = List<T>.of(items);
  if (newIndex > oldIndex) newIndex--;
  copy.insert(newIndex, copy.removeAt(oldIndex));
  return copy;
}

int reorderedActiveIndex(int active, int oldIndex, int newIndex) {
  final destination = newIndex > oldIndex ? newIndex - 1 : newIndex;
  if (active == oldIndex) return destination;
  if (oldIndex < active && destination >= active) return active - 1;
  if (oldIndex > active && destination <= active) return active + 1;
  return active;
}

(List<Track>, int) boundedQueue(
  List<Track> tracks,
  int selected, {
  int limit = 500,
}) {
  if (tracks.isEmpty) return (<Track>[], 0);
  selected = selected.clamp(0, tracks.length - 1);
  final start = selected < limit ? 0 : selected;
  final end = (start + limit).clamp(0, tracks.length);
  final slice = tracks.sublist(start, end);
  final playable = slice.where((t) => t.streamable).toList();
  return (
    playable,
    slice
        .take(selected - start)
        .where((t) => t.streamable)
        .length
        .clamp(0, playable.isEmpty ? 0 : playable.length - 1),
  );
}
