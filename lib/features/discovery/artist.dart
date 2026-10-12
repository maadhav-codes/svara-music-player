class Artist {
  const Artist({
    required this.url,
    required this.name,
    this.artwork,
    this.description = '',
    this.subscribers = -1,
  });
  final String url, name, description;
  final String? artwork;
  final int subscribers;
  String get id => Uri.parse(url).pathSegments.last;
  factory Artist.fromJson(Map<String, dynamic> j) => Artist(
    url: j['url'] as String,
    name: j['name'] as String,
    artwork: j['artwork'] as String?,
    description: j['description'] as String? ?? '',
    subscribers: (j['subscribers'] as num?)?.toInt() ?? -1,
  );
  Map<String, Object?> toJson() => {
    'url': url,
    'name': name,
    'artwork': artwork,
    'description': description,
    'subscribers': subscribers,
  };
}

class MusicCollection {
  const MusicCollection({
    required this.url,
    required this.name,
    required this.artist,
    this.artwork,
    this.count = -1,
  });
  final String url, name, artist;
  final String? artwork;
  final int count;
  factory MusicCollection.fromJson(Map<String, dynamic> j) => MusicCollection(
    url: j['url'] as String,
    name: j['name'] as String,
    artist: j['artist'] as String? ?? '',
    artwork: j['artwork'] as String?,
    count: (j['count'] as num?)?.toInt() ?? -1,
  );
}
