// Live audit; outputs public metadata only, never temporary stream URLs.
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:svara/core/store.dart';
import 'package:svara/features/discovery/regional_youtube_catalog.dart';
import 'package:svara/features/discovery/ranked_discovery.dart';
import 'package:svara/features/discovery/youtube_repository.dart';
import 'package:svara/features/player/svara_handler.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('30 unique regional chart videos: identity and live decode', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: Color(0xfff6f4ee),
          child: Center(
            child: Text(
              'Svara live chart audit running.\nPlease keep the phone connected.',
              style: TextStyle(color: Color(0xff222222), fontSize: 20),
            ),
          ),
        ),
      ),
    );
    final store = await Store.open(path: ':memory:');
    final youtube = YouTubeRepository(store);
    final catalog = RegionalYouTubeCatalog(youtube);
    final matcher = RankedMatcher(youtube);
    final handler = await AudioService.init<SvaraHandler>(
      builder: () => SvaraHandler(store, resolveYouTube: youtube.resolve),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'app.svara.audit.playback',
        androidNotificationChannelName: 'Svara audit playback',
        androidNotificationIcon: 'drawable/ic_notification_svara',
      ),
    );
    String? currentError;
    final errorSubscription = handler.errors.stream.listen(
      (error) => currentError = error,
    );
    final seen = <String>{};
    var sampled = 0, matched = 0, decoded = 0;
    try {
      await handler.initialize();
      await handler.player.setVolume(0);
      for (final market in RegionalYouTubeCatalog.markets.keys) {
        const scope = 'week';
        var source = await catalog.page(market: market, scope: scope);
        final selected = <CatalogRecording>[];
        for (var pages = 0; pages < 8; pages++) {
          for (final song in source.entries) {
            if (selected.length == 15) break;
            if (seen.add(song.key)) selected.add(song);
          }
          if (selected.length == 15 || source.cursor == null) break;
          source = await catalog.page(
            market: market,
            scope: scope,
            cursor: source.cursor,
          );
        }
        expect(
          selected.length,
          15,
          reason: 'Fifteen unique chart videos in $market',
        );
        final samplePage = RankedPage(
          entries: selected,
          sourceName: source.sourceName,
          market: source.market,
          scope: scope,
          periodStart: source.periodStart,
          periodEnd: source.periodEnd,
          chartUrl: source.chartUrl,
          updatedAt: source.updatedAt,
          fetchedAt: source.fetchedAt,
          expiresAt: source.expiresAt,
        );
        final results = await matcher.matchPage(samplePage, CancelToken());
        for (final match in results) {
          sampled++;
          final song = match.recording;
          var playback = false;
          String? playbackError;
          Map<String, Object?>? resolvedMetadata;
          if (match.track != null) {
            matched++;
            try {
              currentError = null;
              await handler.setQueue([match.track!]);
              final deadline = DateTime.now().add(const Duration(seconds: 20));
              while (DateTime.now().isBefore(deadline) &&
                  handler.player.position < const Duration(milliseconds: 800) &&
                  currentError == null) {
                await Future<void>.delayed(const Duration(milliseconds: 200));
              }
              playback =
                  handler.player.position >= const Duration(milliseconds: 800);
              if (playback) decoded++;
              playbackError = currentError;
              resolvedMetadata = handler.current?.toSavedJson();
              await handler.pause();
            } catch (e) {
              playbackError = e.toString();
            }
          }
          debugPrint(
            'SVARA_AUDIT ${jsonEncode({'scope': scope, 'market': market, 'periodStart': source.periodStart?.toIso8601String(), 'periodEnd': source.periodEnd?.toIso8601String(), 'updatedAt': source.updatedAt?.toIso8601String(), 'recordingId': song.id, 'rank': song.rank, 'title': song.title, 'artists': song.artists, 'album': song.album, 'version': song.version, 'durationMs': song.durationMs, 'isrc': song.isrc, 'listenCount': song.listenCount, 'sourceUrl': song.sourceUrl, 'metadataUrl': song.metadataUrl, 'candidate': match.track?.toSavedJson(), 'confidence': match.confidence, 'unmatchedReason': match.reason, 'directChartReference': true, 'decoded': playback, 'playbackError': playbackError, 'resolvedMetadata': resolvedMetadata})}',
          );
        }
      }
      expect(sampled, 30);
      expect(seen.length, 30);
      expect(matched, greaterThan(0));
      debugPrint(
        'SVARA_AUDIT_SUMMARY ${jsonEncode({'sampled': sampled, 'matched': matched, 'decoded': decoded})}',
      );
    } finally {
      await errorSubscription.cancel();
      catalog.dispose();
      await handler.dispose();
      await store.db.close();
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
