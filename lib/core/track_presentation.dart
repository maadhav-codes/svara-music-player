import 'track.dart';

/// Display-only metadata. Never use this for matching, persistence or playback.
class TrackPresentation {
  TrackPresentation(
    this.title,
    Iterable<String> versions,
    Iterable<String> labels,
  ) : versions = List.unmodifiable(versions),
      labels = List.unmodifiable(labels);

  final String title;
  final List<String> versions, labels;

  static final _groups = RegExp(r'\(([^()]*)\)|\[([^\[\]]*)\]');
  static final _separators = RegExp(r'\s*\|\s*|\s+•\s+');
  static final _dashSeparators = RegExp(r'\s+[–—-]\s+');
  static final _space = RegExp(r'\s+');
  static final _quality = RegExp(
    r'^(?:hd|hq|4k|8k|1080p|720p)(?:\s+(?:audio|video))?$',
    caseSensitive: false,
  );
  static final _version = RegExp(
    r'^(?:.*\b(?:remix|mix|remaster(?:ed)?|version|edit)|'
    r'(?:\d{4}\s+)?remaster(?:ed)?(?:\s+\d{4})?|'
    r'live(?:\s+(?:at|in|from|version|session)\b.*)?|'
    r'acoustic|instrumental|karaoke|demo|cover|mono|stereo|'
    r'sped\s+up|slowed(?:\s*(?:\+|and|&)\s*reverb)?)$',
    caseSensitive: false,
  );
  static final _formats = <RegExp, String>{
    RegExp(
      r'^(?:official\s+)?(?:music\s+)?video(?:\s+hd)?$',
      caseSensitive: false,
    ): 'Music video',
    RegExp(
      r'^(?:official\s+)?(?:lyric(?:s)?(?:\s+video)?|lyrics)$',
      caseSensitive: false,
    ): 'Lyrics',
    RegExp(r'^(?:official\s+)?audio$', caseSensitive: false): 'Audio',
    RegExp(r'^(?:official\s+)?visuali[sz]er$', caseSensitive: false):
        'Visualizer',
    RegExp(r'^(?:official\s+)?(?:full\s+)?song$', caseSensitive: false):
        'Audio',
  };

  factory TrackPresentation.fromTrack(Track track) {
    // File tags are curated by the owner; avoid guessing at their contents.
    if (!track.online) {
      return TrackPresentation(track.title, const [], const []);
    }
    final versions = <String>{}, labels = <String>{};
    final artists = <String>{
      track.artist,
      track.recordingArtist,
      track.artist.replaceFirst(
        RegExp(r'\s*-\s*Topic$', caseSensitive: false),
        '',
      ),
    }.map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toSet();
    final artistNames = artists.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    bool extract(String raw) {
      final value = raw.trim().replaceAll(_space, ' ');
      if (_version.hasMatch(value)) {
        versions.add(value);
        return true;
      }
      for (final entry in _formats.entries) {
        if (entry.key.hasMatch(value)) {
          labels.add(entry.value);
          return true;
        }
      }
      return _quality.hasMatch(value);
    }

    final parts = <String>[];
    final segments = <String>[];
    for (var chunk in track.title.split(_separators)) {
      chunk = chunk.trim();
      if (artists.contains(chunk.toLowerCase())) continue;
      // Match whole uploader names before splitting hyphens in "Artist - Topic".
      for (final artist in artistNames) {
        chunk = chunk.replaceFirst(
          RegExp(
            '^${RegExp.escape(artist)}\\s+[–—-]\\s+',
            caseSensitive: false,
          ),
          '',
        );
        chunk = chunk.replaceFirst(
          RegExp(
            '\\s+[–—-]\\s+${RegExp.escape(artist)}\$',
            caseSensitive: false,
          ),
          '',
        );
      }
      segments.addAll(chunk.split(_dashSeparators));
    }
    for (final raw in segments) {
      final part = raw.trim();
      if (artists.contains(part.toLowerCase()) ||
          (parts.isNotEmpty && extract(part))) {
        continue;
      }
      final clean = part
          .replaceAllMapped(_groups, (match) {
            return extract(match[1] ?? match[2]!) ? '' : match[0]!;
          })
          .replaceAll(_space, ' ')
          .trim();
      if (clean.isNotEmpty) parts.add(clean);
    }
    // Never turn a legitimate title such as "Live" or "Audio" into a badge.
    if (parts.isEmpty) {
      return TrackPresentation(track.title, const [], const []);
    }
    if (track.musicCatalogSong) labels.add('Songs catalog');
    return TrackPresentation(parts.join(' · '), versions, labels);
  }
}

extension TrackDisplayMetadata on Track {
  TrackPresentation get presentation => TrackPresentation.fromTrack(this);
}
