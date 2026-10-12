import 'package:dio/dio.dart';

import '../../core/track.dart';
import 'ranked_discovery.dart';
import 'youtube_repository.dart';

/// YouTube's own regional Top 100 Songs chart. Entries already carry their
/// playback video ID; no catalog-to-video search or inferred artist is needed.
class RegionalYouTubeCatalog extends DiscoveryCatalog {
  RegionalYouTubeCatalog(this.youtube, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final YouTubeRepository youtube;
  final DateTime Function() now;
  static const markets = {'in': 'India', 'gb': 'United Kingdom'};
  static const playlistIds = {
    'in': 'PL4fGSI1pDJn4pTWyM3t61lOyZ6_4jcNOw',
    'gb': 'PL4fGSI1pDJn6_f5P3MnzXg9l3GDfnSlXa',
  };
  final _snapshots = <String, RankedPage>{};
  @override
  bool get configured => true;
  @override
  Future<BrowseCapabilities> capabilities({CancelToken? cancel}) async {
    if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
    return const BrowseCapabilities(
      markets,
      [],
      scopes: {'week': 'Weekly Top 100'},
      browseTitle: 'Popular songs',
      preferenceDescription: 'YouTube’s regional Top 100 Songs chart. Chart market is not recording language.',
    );
  }

  @override
  Future<RankedPage> page({
    required String market,
    String? genre,
    String scope = 'week',
    String? cursor,
    CancelToken? cancel,
  }) async {
    if (!markets.containsKey(market) || genre != null || scope != 'week') {
      throw const FormatException('Unsupported regional chart.');
    }
    if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
    RankedPage snapshot;
    var offset = 0;
    if (cursor == null) {
      final data = await youtube.musicCharts(
        market.toUpperCase(),
        cancel: cancel,
      );
      if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
      if (data['country'] != market.toUpperCase() ||
          data['name'] != 'Top 100 Songs ${markets[market]}' ||
          data['ownerUrl'] !=
              'https://www.youtube.com/channel/UCrKZcyOJVWnJ60zM1XWllNw') {
        throw const FormatException('Different chart returned.');
      }
      final rows = data['tracks'] as List;
      if (rows.length > 100) throw const FormatException('Chart is too large.');
      final ids = <String>{};
      final entries = <CatalogRecording>[];
      var previousRank = 0;
      final source = data['sourceUrl'] as String;
      final sourceUri = Uri.tryParse(source);
      if (sourceUri?.scheme != 'https' ||
          sourceUri?.host != 'www.youtube.com' ||
          sourceUri?.path != '/playlist' ||
          sourceUri?.queryParameters['list'] != playlistIds[market]) {
        throw const FormatException('Invalid chart source.');
      }
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final rank = row['rank'] as int;
        if (rank <= previousRank) {
          throw const FormatException('Chart order is invalid.');
        }
        previousRank = rank;
        final Track reference = youtube.chartTrack(row);
        if (!ids.add(reference.id)) continue;
        entries.add(
          CatalogRecording(
            id: reference.id,
            title: reference.title,
            artists: const [],
            rank: rank,
            sourceUrl: source,
            durationMs: reference.durationMs > 0 ? reference.durationMs : null,
            playback: reference,
          ),
        );
      }
      final fetched = now().toUtc();
      snapshot = RankedPage(
        entries: entries,
        sourceName: 'YouTube Charts',
        market: market,
        scope: scope,
        ranking: 'most-played',
        chartUrl: source,
        fetchedAt: fetched,
        expiresAt: fetched.add(const Duration(minutes: 15)),
      );
      _snapshots[market] = snapshot;
    } else {
      final parts = cursor.split(':');
      final saved = _snapshots[market];
      if (parts.length != 3 ||
          parts[0] != market ||
          saved == null ||
          parts[1] != '${saved.fetchedAt.microsecondsSinceEpoch}' ||
          !saved.expiresAt.isAfter(now())) {
        throw const FormatException('Chart expired. Refresh to continue.');
      }
      offset = int.tryParse(parts[2]) ?? -1;
      if (offset < 0 || offset >= saved.entries.length || offset % 10 != 0) {
        throw const FormatException('Invalid chart page.');
      }
      snapshot = saved;
    }
    final entries = snapshot.entries.skip(offset).take(10).toList();
    final next = offset + entries.length;
    return RankedPage(
      entries: entries,
      sourceName: snapshot.sourceName,
      market: market,
      scope: scope,
      ranking: snapshot.ranking,
      chartUrl: snapshot.chartUrl,
      fetchedAt: snapshot.fetchedAt,
      expiresAt: snapshot.expiresAt,
      cursor: next < snapshot.entries.length
          ? '$market:${snapshot.fetchedAt.microsecondsSinceEpoch}:$next'
          : null,
    );
  }
}
