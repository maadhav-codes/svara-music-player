// Separate live smoke test: not part of deterministic unit-test CI.

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:svara/core/store.dart';
import 'package:svara/core/track.dart';
import 'package:svara/features/discovery/youtube_repository.dart';
import 'package:svara/features/player/svara_handler.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'live Android extraction, decoding, seek, and optional background smoke test',
    (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: Color(0xfff6f4ee),
            child: Center(
              child: Text(
                'Svara playback test running.\nPlease keep this app open.',
                style: TextStyle(fontSize: 20, color: Color(0xff21594b)),
              ),
            ),
          ),
        ),
      );
      final store = await Store.open(path: ':memory:');
      final youtube = YouTubeRepository(store);
      final handler = await AudioService.init<SvaraHandler>(
        builder: () => SvaraHandler(store, resolveYouTube: youtube.resolve),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'app.svara.playback',
          androidNotificationChannelName: 'Svara playback',
          androidNotificationIcon: 'drawable/ic_notification_svara',
        ),
      );
      try {
        await handler.initialize();
        await handler.player.setVolume(
          0,
        ); // Decode without making the test audible.
        // Blender's openly licensed Big Buck Bunny; no mainstream recording fixture.
        const reference = Track(
          id: 'youtube:aqz-KE-bpKQ',
          title: 'Big Buck Bunny',
          artist: 'Blender',
          uri: 'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
        );
        final watch = Stopwatch()..start();
        final resolved = await youtube.resolve(reference);
        debugPrint(
          'SVARA_PROBE resolve_ms=${watch.elapsedMilliseconds} mime=${resolved.stream.mimeType} codec=${resolved.stream.codec}',
        );
        expect(resolved.track.durationMs, greaterThan(0));
        expect(resolved.stream.uri.scheme, 'https');
        final page = await youtube.search('Kevin MacLeod music');
        expect(page.tracks, isNotEmpty);
        expect(
          page.tracks.every(
            (t) => t.durationMs >= 45000 && t.durationMs <= 1200000,
          ),
          isTrue,
        );
        if (page.continuation != null) {
          final next = await youtube.search(
            'Kevin MacLeod music',
            continuation: page.continuation,
          );
          // Filtering may legitimately leave a page empty with more pages available.
          expect(
            next.tracks.every(
              (t) => t.durationMs >= 45000 && t.durationMs <= 1200000,
            ),
            isTrue,
          );
        }
        watch.reset();
        await handler.setQueue([reference]);
        final started = DateTime.now();
        while (handler.player.position < const Duration(seconds: 1) &&
            DateTime.now().difference(started) < const Duration(seconds: 20)) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        expect(
          handler.player.position,
          greaterThanOrEqualTo(const Duration(seconds: 1)),
        );
        debugPrint(
          'SVARA_PROBE playback_start_ms=${watch.elapsedMilliseconds}',
        );
        await handler.seek(const Duration(seconds: 20));
        expect(handler.player.position.inSeconds, greaterThanOrEqualTo(19));
        debugPrint('SVARA_PROBE BACKGROUND_READY');
        // During this window adb can send HOME to verify activity-independent playback.
        const backgroundSeconds = int.fromEnvironment(
          'BACKGROUND_SECONDS',
          defaultValue: 3,
        );
        await Future<void>.delayed(const Duration(seconds: backgroundSeconds));
        expect(handler.player.position.inSeconds, greaterThan(21));
        await handler.pause();
        expect(handler.player.playing, false);
        await handler.save();
        expect(
          (await store.read('playback')).toString(),
          isNot(contains('googlevideo')),
        );
        debugPrint(
          'SVARA_PROBE position_s=${handler.player.position.inSeconds} PASSED',
        );
      } finally {
        await handler.dispose();
        await store.db.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
