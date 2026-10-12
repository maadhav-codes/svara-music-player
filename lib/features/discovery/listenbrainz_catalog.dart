import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/memory_cache.dart';
import 'ranked_discovery.dart';

/// Public aggregate rankings plus CC0 MusicBrainz recording metadata. No user
/// token, personal history, tags, artwork or third-party playback URLs requested.
class ListenBrainzCatalog extends DiscoveryCatalog {
  ListenBrainzCatalog({
    super.dio,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  }) : now = now ?? DateTime.now,
       delay = delay ?? Future<void>.delayed;
  final DateTime Function() now;
  final Future<void> Function(Duration) delay;
  static const scopes = {
    'week': 'Weekly',
    'month': 'Monthly',
    'year': 'Yearly',
  };
  static const userAgent =
      'Svara/3.1.0 (https://github.com/maadhav-codes/svara-music-player)';
  static final _mbid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  Future<void> _pending = Future<void>.value();
  DateTime _nextRequest = DateTime.fromMillisecondsSinceEpoch(0);
  late final _recordings = MemoryCache<String, Map<String, dynamic>>(
    capacity: 200,
    ttl: const Duration(days: 1),
    now: now,
  );

  @override
  bool get configured => true;

  @override
  Future<BrowseCapabilities> capabilities({CancelToken? cancel}) async {
    if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
    return const BrowseCapabilities(
      {'global': 'ListenBrainz community'},
      [],
      scopes: scopes,
      browseTitle: 'Popular on ListenBrainz',
    );
  }

  /// Serializes both APIs and obeys their one-request-per-second policies,
  /// including queued cancellations and server Retry-After/rate-reset headers.
  Future<Map<String, dynamic>?> _request(
    String url,
    Map<String, Object?> query,
    CancelToken? cancel,
  ) {
    final result = _pending.then((_) async {
      if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
      final wait = _nextRequest.difference(now());
      if (wait > Duration.zero) {
        await Future.any<void>([
          delay(wait),
          if (cancel != null)
            cancel.whenCancel.then<void>((error) => throw error),
        ]);
      }
      if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
      _nextRequest = now().add(const Duration(milliseconds: 1100));
      try {
        final response = await dio.get<Map<String, dynamic>>(
          url,
          queryParameters: query,
          cancelToken: cancel,
          options: Options(
            headers: {'User-Agent': userAgent, 'Accept': 'application/json'},
          ),
        );
        if (response.headers.value('x-ratelimit-remaining') == '0') {
          final reset = int.tryParse(
            response.headers.value('x-ratelimit-reset-in') ?? '',
          );
          if (reset != null && reset > 0) {
            _nextRequest = now().add(Duration(seconds: reset));
          }
        }
        if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
        if (response.statusCode == 204) return null;
        return response.data ??
            (throw const FormatException('Empty catalog response.'));
      } on DioException catch (e) {
        final retry = int.tryParse(
          e.response?.headers.value('retry-after') ??
              e.response?.headers.value('x-ratelimit-reset-in') ??
              '',
        );
        if (retry != null && retry > 0) {
          _nextRequest = now().add(Duration(seconds: retry));
        }
        rethrow;
      }
    });
    _pending = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<RankedPage> page({
    required String market,
    String? genre,
    String scope = 'week',
    String? cursor,
    CancelToken? cancel,
  }) async {
    if (market != 'global' || genre != null || !scopes.containsKey(scope)) {
      throw const FormatException(
        'This chart supports the ListenBrainz community and reporting periods only.',
      );
    }
    // Cursor pins pagination to the same source update, preventing mixed charts.
    final parts = cursor?.split(':');
    final offset = parts == null
        ? 0
        : parts.length == 3 && parts[0] == scope
        ? int.tryParse(parts[2])
        : null;
    if (offset == null ||
        offset < 0 ||
        offset > 990 ||
        (parts != null && int.tryParse(parts[1]) == null)) {
      throw const FormatException('Invalid chart page.');
    }
    const url = 'https://api.listenbrainz.org/1/stats/sitewide/recordings';
    final data = await _request(url, {
      'range': scope,
      'count': 10,
      'offset': offset,
    }, cancel);
    final fetched = now().toUtc();
    if (data == null) {
      return RankedPage(
        entries: const [],
        sourceName: 'ListenBrainz',
        market: market,
        scope: scope,
        fetchedAt: fetched,
        expiresAt: fetched.add(const Duration(hours: 1)),
      );
    }
    final payload = Map<String, dynamic>.from(data['payload'] as Map);
    if (payload['range'] != scope || payload['offset'] != offset) {
      throw const FormatException('Different chart returned.');
    }
    final updated = (payload['last_updated'] as num).toInt();
    if (parts != null && parts[1] != '$updated') {
      throw const FormatException(
        'The chart was updated. Refresh to continue.',
      );
    }
    final start = DateTime.fromMillisecondsSinceEpoch(
      (payload['from_ts'] as num).toInt() * 1000,
      isUtc: true,
    );
    final end = DateTime.fromMillisecondsSinceEpoch(
      (payload['to_ts'] as num).toInt() * 1000,
      isUtc: true,
    );
    final updateTime = DateTime.fromMillisecondsSinceEpoch(
      updated * 1000,
      isUtc: true,
    );
    if (!end.isAfter(start) ||
        updateTime.isAfter(fetched.add(const Duration(minutes: 5)))) {
      throw const FormatException('Invalid chart timestamps.');
    }
    final rows = payload['recordings'] as List;
    if (rows.length > 10) throw const FormatException('Chart page too large.');
    final entries = <CatalogRecording>[];
    final seen = <String>{};
    int? previousCount;
    final chartUrl = 'https://listenbrainz.org/statistics/?range=$scope';
    for (var i = 0; i < rows.length; i++) {
      if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
      final row = Map<String, dynamic>.from(rows[i] as Map);
      final count = (row['listen_count'] as num).toInt();
      if (count < 0 || (previousCount != null && count > previousCount)) {
        throw const FormatException('Chart counts are out of order.');
      }
      previousCount = count;
      final id = row['recording_mbid'] as String?;
      final identity = id != null && _mbid.hasMatch(id)
          ? id
          : 'unmapped:$scope:${offset + i}';
      if (!seen.add(identity)) continue;
      Map<String, dynamic>? recording;
      if (id != null && _mbid.hasMatch(id)) {
        recording = _recordings.get(id);
        if (recording == null) {
          try {
            recording = await _request(
              'https://musicbrainz.org/ws/2/recording/$id',
              {'fmt': 'json', 'inc': 'artist-credits+isrcs'},
              cancel,
            );
            if (recording != null && recording['id'] == id) {
              _recordings.put(id, recording);
            } else {
              recording = null;
            }
          } on DioException catch (e) {
            if (cancel?.isCancelled ?? false) rethrow;
            if ({429, 503}.contains(e.response?.statusCode)) rethrow;
            // Metadata outages disable this entry; never invent duration/artist.
          }
        }
      }
      final title =
          recording?['title'] as String? ?? row['track_name'] as String;
      final credits = recording?['artist-credit'] as List?;
      final artists = credits == null
          ? [row['artist_name'] as String]
          : credits.map((a) => (a as Map)['name'] as String).toList();
      final length = credits != null && credits.isNotEmpty
          ? (recording?['length'] as num?)?.toInt()
          : null;
      final isrcs = recording?['isrcs'] as List? ?? [];
      final disambiguation = recording?['disambiguation'] as String? ?? '';
      // Never lose an alternate-version qualifier from the source identity.
      final alternate = RegExp(
        r'\b(live|remix|acoustic|instrumental|edit)\b',
        caseSensitive: false,
      ).hasMatch(disambiguation);
      entries.add(
        CatalogRecording(
          id: identity,
          title: title,
          artists: artists,
          rank: offset + i + 1,
          sourceUrl: chartUrl,
          metadataUrl: id != null && _mbid.hasMatch(id)
              ? 'https://musicbrainz.org/recording/$id'
              : null,
          album: row['release_name'] as String?,
          version: alternate ? disambiguation : null,
          durationMs: length != null && length > 0 ? length : null,
          isrc: isrcs.isEmpty ? null : isrcs.first as String,
          listenCount: count,
        ),
      );
    }
    final next = offset + rows.length;
    final total = (payload['total_recording_count'] as num).toInt();
    return RankedPage(
      entries: entries,
      sourceName: 'ListenBrainz',
      market: market,
      scope: scope,
      periodStart: start,
      periodEnd: end,
      chartUrl: chartUrl,
      updatedAt: updateTime,
      fetchedAt: fetched,
      expiresAt: fetched.add(const Duration(hours: 1)),
      cursor: rows.isNotEmpty && next < total && next < 1000
          ? '$scope:$updated:$next'
          : null,
    );
  }
}
