import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/memory_cache.dart';
import '../../core/track.dart';
import 'discovery_category.dart';
import 'youtube_repository.dart';
import '../../core/providers.dart';
import 'regional_youtube_catalog.dart';

final discoveryCatalogProvider = Provider((ref) {
  const endpoint = String.fromEnvironment('DISCOVERY_CATALOG_URL');
  final catalog = endpoint.isEmpty
      ? RegionalYouTubeCatalog(ref.read(youtubeProvider))
      : DiscoveryCatalog(endpoint: endpoint);
  ref.onDispose(catalog.dispose);
  return catalog;
});

/// The endpoint must be backed by a licensed, reviewed source. No provider
/// credential belongs in this client. No history/follows are sent here.
class DiscoveryCatalog {
  DiscoveryCatalog({
    Dio? dio,
    this.endpoint = const String.fromEnvironment('DISCOVERY_CATALOG_URL'),
  }) : dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 20),
             ),
           );
  final Dio dio;
  final String endpoint;
  bool get configured => endpoint.isNotEmpty;
  void dispose() => dio.close();

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, Object?> query,
    CancelToken? cancel,
  ) async {
    final base = Uri.tryParse(endpoint);
    if (base == null ||
        base.scheme != 'https' ||
        base.host.isEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw const FormatException(
        'Popular music is not available yet. Search songs or artists above.',
      );
    }
    final response = await dio.get<Map<String, dynamic>>(
      '${endpoint.replaceFirst(RegExp(r'/$'), '')}/$path',
      queryParameters: query,
      cancelToken: cancel,
    );
    if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
    return response.data ??
        (throw const FormatException('The music catalog returned no data.'));
  }

  Future<BrowseCapabilities> capabilities({CancelToken? cancel}) async =>
      BrowseCapabilities.fromJson(await _get('capabilities', {}, cancel));

  Future<RankedPage> page({
    required String market,
    String? genre,
    String scope = 'week',
    String? cursor,
    CancelToken? cancel,
  }) async {
    final json = await _get('charts', {
      'market': market,
      'scope': scope,
      'genre': ?genre,
      'cursor': ?cursor,
      'limit': 10,
    }, cancel);
    final page = RankedPage.fromJson(json);
    if (page.market != market ||
        page.scope != scope ||
        page.genre != genre ||
        page.entries.length > 10 ||
        !page.expiresAt.isAfter(DateTime.now())) {
      throw const FormatException(
        'The catalog returned an expired or different chart. Please retry.',
      );
    }
    return page;
  }
}

class BrowseCapabilities {
  const BrowseCapabilities(
    this.markets,
    this.genres, {
    this.scopes = const {},
    this.browseTitle,
    this.preferenceDescription,
  });
  final Map<String, String> scopes;
  final String? browseTitle, preferenceDescription;
  final Map<String, String> markets;
  final List<DiscoveryCategory> genres;
  factory BrowseCapabilities.fromJson(Map<String, dynamic> json) =>
      BrowseCapabilities(
        Map<String, String>.from(json['markets'] as Map),
        (json['genres'] as List)
            .map(
              (g) => DiscoveryCategory(g['id'] as String, g['label'] as String),
            )
            .toList(),
        scopes: Map<String, String>.from(json['scopes'] as Map? ?? {}),
        browseTitle: json['browseTitle'] as String?,
        preferenceDescription: json['preferenceDescription'] as String?,
      );
}

class CatalogRecording {
  const CatalogRecording({
    required this.id,
    required this.title,
    required this.artists,
    required this.rank,
    required this.sourceUrl,
    this.album,
    this.version,
    this.durationMs,
    this.isrc,
    this.genres = const [],
    this.listenCount,
    this.metadataUrl,
    this.playback,
  });
  final String id, title, sourceUrl;
  final List<String> artists, genres;
  final int rank;
  final int? listenCount;
  final String? metadataUrl;
  final Track? playback;
  final String? album, version, isrc;
  final int? durationMs;
  String get key => '${isrc ?? id}:${version ?? ''}';
  factory CatalogRecording.fromJson(Map<String, dynamic> j) => CatalogRecording(
    listenCount: j['listenCount'] as int?,
    metadataUrl: j['metadataUrl'] as String?,
    id: j['id'] as String,
    title: j['title'] as String,
    artists: List<String>.from(j['artists'] as List),
    rank: j['rank'] as int,
    sourceUrl: j['sourceUrl'] as String,
    album: j['album'] as String?,
    version: j['version'] as String?,
    durationMs: j['durationMs'] as int?,
    isrc: j['isrc'] as String?,
    genres: List<String>.from(j['genres'] as List? ?? []),
  );
}

class RankedPage {
  const RankedPage({
    required this.entries,
    required this.sourceName,
    required this.market,
    required this.fetchedAt,
    required this.expiresAt,
    this.updatedAt,
    this.scope = 'week',
    this.ranking = 'most-played',
    this.periodStart,
    this.periodEnd,
    this.chartUrl,
    this.genre,
    this.cursor,
  });
  final List<CatalogRecording> entries;
  final String sourceName, market, scope, ranking;
  final DateTime? periodStart, periodEnd;
  final String? chartUrl;
  final String? genre, cursor;
  final DateTime fetchedAt, expiresAt;
  final DateTime? updatedAt;
  factory RankedPage.fromJson(Map<String, dynamic> j) {
    if (j['ranking'] != 'most-played' ||
        (j['sourceName'] as String).trim().isEmpty) {
      throw const FormatException('Unsupported chart ranking.');
    }
    final seen = <String>{};
    final entries = (j['entries'] as List)
        .map(
          (e) => CatalogRecording.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .where((e) => seen.add(e.key))
        .toList();
    if (entries.length > 10) {
      throw const FormatException('Chart page is too large.');
    }
    var rank = 0;
    for (final entry in entries) {
      if (entry.rank <= rank ||
          entry.id.isEmpty ||
          entry.artists.isEmpty ||
          entry.artists.any((a) => a.trim().isEmpty) ||
          entry.title.isEmpty ||
          Uri.tryParse(entry.sourceUrl)?.scheme != 'https' ||
          (j['genre'] != null && !entry.genres.contains(j['genre']))) {
        throw const FormatException(
          'Missing chart order or category evidence.',
        );
      }
      rank = entry.rank;
    }
    return RankedPage(
      entries: entries,
      scope: j['scope'] as String? ?? 'week',
      periodStart: j['periodStart'] == null
          ? null
          : DateTime.parse(j['periodStart'] as String),
      periodEnd: j['periodEnd'] == null
          ? null
          : DateTime.parse(j['periodEnd'] as String),
      chartUrl: j['chartUrl'] as String?,
      sourceName: j['sourceName'] as String,
      market: j['market'] as String,
      genre: j['genre'] as String?,
      cursor: j['cursor'] as String?,
      fetchedAt: DateTime.now().toUtc(),
      expiresAt: DateTime.parse(j['expiresAt'] as String),
      updatedAt: j['updatedAt'] == null
          ? null
          : DateTime.parse(j['updatedAt'] as String),
    );
  }
}

class RecordingMatch {
  const RecordingMatch(
    this.recording, {
    this.track,
    this.confidence = 0,
    this.reason,
  });
  final CatalogRecording recording;
  final Track? track;
  final double confidence;
  final String? reason;
}

/// Conservative metadata matching, audited on a limited live sample.
/// Requires duration, exact title/version, all artists and either a Topic/VEVO
/// channel or a song-catalog result with a valid YouTube Music artist URL.
class RankedMatcher {
  RankedMatcher(this.youtube);
  final YouTubeRepository youtube;
  final _cache = MemoryCache<String, ({Track track, DateTime expiresAt})>(
    capacity: 100,
    ttl: const Duration(hours: 1),
  );
  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
  static final _versions = RegExp(
    r'\b(cover|remix|karaoke|slowed|sped|live|reaction|compilation|acoustic|instrumental|remaster|edit)\b',
    caseSensitive: false,
  );

  static double confidence(CatalogRecording song, Track candidate) {
    if (song.artists.isEmpty ||
        !candidate.streamable ||
        song.durationMs == null ||
        candidate.durationMs <= 0 ||
        (song.durationMs! - candidate.durationMs).abs() >
            min(5000, song.durationMs! * .025)) {
      return 0;
    }
    final expected = normalize('${song.title} ${song.version ?? ''}');
    final candidateVersions = _versions
        .allMatches(candidate.title)
        .map((m) => m[0]!.toLowerCase())
        .toSet();
    final wantedVersions = _versions
        .allMatches('${song.title} ${song.version ?? ''}')
        .map((m) => m[0]!.toLowerCase())
        .toSet();
    if (candidateVersions.difference(wantedVersions).isNotEmpty) return 0;
    final uploader = normalize(
      candidate.artist.replaceFirst(
        RegExp(r'\s*-\s*topic$|vevo$', caseSensitive: false),
        '',
      ),
    );
    final artistUrl = Uri.tryParse(candidate.uploaderUrl ?? '');
    final musicArtist =
        candidate.musicCatalogSong &&
        artistUrl?.scheme == 'https' &&
        {
          'www.youtube.com',
          'music.youtube.com',
          'youtube.com',
        }.contains(artistUrl?.host) &&
        RegExp(r'^/channel/UC[A-Za-z0-9_-]{22}$')
            .hasMatch(artistUrl?.path ?? '');
    if (!musicArtist &&
        !RegExp(
          r'(?:-\s*topic|vevo)$',
          caseSensitive: false,
        ).hasMatch(candidate.artist.trim())) {
      return 0;
    }
    final artistNames = song.artists.map(normalize).toList();
    final artistEvidence = normalize('$uploader ${candidate.title}');
    if (artistNames.any(
      (a) => a.isEmpty || !(' $artistEvidence ').contains(' $a '),
    )) {
      return 0;
    }
    var title = candidate.title.replaceAll(
      RegExp(
        r'\((?:official audio|official video|lyrics?|audio)\)|\[(?:official audio|official video|lyrics?|audio)\]',
        caseSensitive: false,
      ),
      '',
    );
    title = normalize(title);
    // Accept an exact recording title or an artist-prefixed exact title.
    final forms = {
      expected,
      for (final artist in artistNames) '$artist $expected',
    };
    return forms.contains(title) ? .95 : 0;
  }

  Future<List<RecordingMatch>> matchPage(
    RankedPage page,
    CancelToken cancel,
  ) async {
    final results = List<RecordingMatch?>.filled(page.entries.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < page.entries.length) {
        if (cancel.isCancelled) throw cancel.cancelError!;
        final i = next++;
        final song = page.entries[i];
        final key =
            '${page.sourceName}:${song.key}:${song.title}:${song.artists.join(',')}:${song.durationMs}';
        if (song.playback != null) {
          final direct = song.playback!;
          results[i] = RecordingMatch(
            song,
            track: direct.streamable
                ? Track.fromJson({
                    ...direct.toJson(),
                    'catalog': {
                      'id': song.id,
                      'title': song.title,
                      'artists': song.artists,
                      'rank': song.rank,
                      'market': page.market,
                      'scope': page.scope,
                      'ranking': page.ranking,
                      'sourceName': page.sourceName,
                      'sourceUrl': song.sourceUrl,
                      'chartUrl': page.chartUrl,
                      'fetchedAt': page.fetchedAt.toIso8601String(),
                      'updatedAt': page.updatedAt?.toIso8601String(),
                      'directChartReference': true,
                    },
                  })
                : null,
            confidence: direct.streamable ? 1 : 0,
            reason: direct.streamable ? null : 'Chart video is unavailable',
          );
          continue;
        }
        if (song.durationMs == null || song.durationMs! <= 0) {
          results[i] = RecordingMatch(
            song,
            reason: 'Recording duration is unavailable',
          );
          continue;
        }
        try {
          final cached = _cache.get(key);
          var track = cached != null && cached.expiresAt.isAfter(DateTime.now())
              ? cached.track
              : null;
          if (track == null) {
            final candidates = await youtube.search(
              '${song.artists.join(' ')} ${song.title} ${song.version ?? ''}',
              cancel: cancel,
            );
            final matches = candidates.tracks
                .where((t) => confidence(song, t) >= .95)
                .toList();
            if (matches.isNotEmpty) {
              track = matches.first;
              _cache.put(key, (track: track, expiresAt: page.expiresAt));
            }
          }
          if (cancel.isCancelled) throw cancel.cancelError!;
          results[i] = RecordingMatch(
            song,
            track: track == null
                ? null
                : Track.fromJson({
                    ...track.toJson(),
                    'catalog': {
                      'id': song.id,
                      'title': song.title,
                      'artists': song.artists,
                      'album': song.album,
                      'version': song.version,
                      'durationMs': song.durationMs,
                      'isrc': song.isrc,
                      'rank': song.rank,
                      'listenCount': song.listenCount,
                      'matchingConfidence': .95,
                      'matchedTitle': track.title,
                      'matchedUploader': track.artist,
                      'matchedUploaderUrl': track.uploaderUrl,
                      'matchedAsMusicCatalogSong': track.musicCatalogSong,
                      'metadataUrl': song.metadataUrl,
                      'scope': page.scope,
                      'periodStart': page.periodStart?.toIso8601String(),
                      'periodEnd': page.periodEnd?.toIso8601String(),
                      'chartUrl': page.chartUrl,
                      'genres': song.genres,
                      'market': page.market,
                      'sourceName': page.sourceName,
                      'sourceUrl': song.sourceUrl,
                      'updatedAt': page.updatedAt?.toIso8601String(),
                      'fetchedAt': page.fetchedAt.toIso8601String(),
                    },
                  }),
            confidence: track == null ? 0 : .95,
            reason: track == null ? 'No verified recording on YouTube' : null,
          );
        } catch (e) {
          if (cancel.isCancelled) rethrow;
          results[i] = RecordingMatch(
            song,
            reason: 'YouTube matching unavailable. Retry.',
          );
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < min(2, page.entries.length); i++) worker(),
    ]);
    final videos = <String>{};
    return results
        .cast<RecordingMatch>()
        .map(
          (m) => m.track != null && !videos.add(m.track!.id)
              ? RecordingMatch(
                  m.recording,
                  reason: 'Duplicate playback recording',
                )
              : m,
        )
        .toList();
  }
}
