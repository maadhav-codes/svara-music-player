// Preserve the public constructor used by legacy local/Audius repositories.
// ignore_for_file: prefer_initializing_formals
import 'media_source.dart';

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
    bool online = false,
    MediaSource? source,
    this.streamable = true,
    this.modified = 0,
  }) : _online = online,
       _source = source;
  final String id, title, artist, uri, album, folder;
  final String? artwork, artistId;
  final int durationMs, modified;
  final bool _online, streamable;
  final MediaSource? _source;
  MediaSource get source =>
      _source ??
      (id.startsWith('youtube:')
          ? MediaSource.youtube
          : _online || id.startsWith('audius:')
          ? MediaSource.audius
          : MediaSource.local);
  bool get online => source != MediaSource.local;
  String get providerId => id.substring(id.indexOf(':') + 1);
  String get sourceUrl => switch (source) {
    MediaSource.youtube => 'https://www.youtube.com/watch?v=$providerId',
    MediaSource.audius => 'https://audius.co',
    MediaSource.local => uri,
  };
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
    'source': source.name,
    'streamable': streamable,
    'modified': modified,
  };
  // Online selections persist identifiers, never signed URLs or API credentials.
  // Audius metadata must remain session-only; use placeholders until resolved.
  Map<String, Object?> toSavedJson() => online
      ? {
          'id': id,
          'title': source == MediaSource.youtube
              ? title
              : '${source.label} track',
          'artist': source == MediaSource.youtube ? artist : source.label,
          if (source == MediaSource.youtube) 'durationMs': durationMs,
          'uri': sourceUrl,
          'online': true,
          'source': source.name,
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
    source: MediaSource.values.where((s) => s.name == j['source']).firstOrNull,
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
