import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../../core/media_source.dart';
import '../../core/store.dart';
import '../../core/track.dart';
import '../player/source_resolver.dart';

class YouTubePage {
  const YouTubePage(this.tracks, this.continuation);
  final List<Track> tracks;
  final String? continuation;
}

/// The channel is registered as an engine plugin so background playback remains
/// independent of the Android activity's lifetime.
class YouTubeRepository {
  YouTubeRepository(
    this.store, {
    this.channel = const MethodChannel('app.svara/youtube'),
    Future<void> Function(Duration)? delay,
    DateTime Function()? now,
    Random? random,
  }) : delay = delay ?? Future<void>.delayed,
       now = now ?? DateTime.now,
       random = random ?? Random();
  final Store store;
  final MethodChannel channel;
  final Future<void> Function(Duration) delay;
  final DateTime Function() now;
  final Random random;
  bool enabled = true;
  StreamQuality quality = StreamQuality.standard;
  int _requestId = 0;

  Future<void> loadSettings() async {
    enabled = await store.read('youtubeEnabled') != false;
    final saved = await store.read('streamQuality');
    quality =
        StreamQuality.values.where((q) => q.name == saved).firstOrNull ??
        StreamQuality.standard;
  }

  Future<void> configure({bool? enabled, StreamQuality? quality}) async {
    if (enabled != null) {
      this.enabled = enabled;
      await store.write('youtubeEnabled', enabled);
    }
    if (quality != null) {
      this.quality = quality;
      await store.write('streamQuality', quality.name);
    }
  }

  Future<Map<String, dynamic>> _call(
    String method,
    Map<String, Object?> args, {
    CancelToken? cancel,
  }) async {
    if (!enabled) {
      throw const SourceException(
        'disabled',
        'YouTube is disabled in Settings. Phone music and Audius are still available.',
      );
    }
    for (var attempt = 0; attempt < 3; attempt++) {
      if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
      final requestId = '${++_requestId}';
      var finished = false;
      if (cancel != null) {
        unawaited(
          cancel.whenCancel.then((_) async {
            if (!finished) {
              try {
                await channel.invokeMethod<void>('cancel', {
                  'requestId': requestId,
                });
              } catch (_) {}
            }
          }),
        );
      }
      try {
        final value = await channel
            .invokeMapMethod<String, dynamic>(method, {
              ...args,
              'requestId': requestId,
            })
            .timeout(const Duration(seconds: 35));
        if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
        if (value == null) {
          throw const SourceException(
            'invalid',
            'YouTube returned an invalid response.',
          );
        }
        return value;
      } on TimeoutException {
        unawaited(
          channel
              .invokeMethod<void>('cancel', {'requestId': requestId})
              .catchError((Object _) {}),
        );
        if (attempt == 2) {
          throw const SourceException(
            'timeout',
            'YouTube timed out. Retry or choose phone music in Library.',
          );
        }
      } on MissingPluginException {
        throw const SourceException(
          'unsupported',
          'YouTube extraction is available in the Android app.',
        );
      } on PlatformException catch (e) {
        if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
        final details = e.details;
        final seconds = details is Map
            ? (details['retryAfter'] as num?)?.toInt()
            : null;
        final failure = SourceException(
          e.code,
          _message(e.code),
          retryAfter: seconds == null
              ? null
              : Duration(seconds: seconds.clamp(1, 8)),
        );
        if (!failure.transient || attempt == 2) throw failure;
        await delay(
          failure.retryAfter ??
              Duration(
                milliseconds: 400 * (1 << attempt) + random.nextInt(150),
              ),
        );
        continue;
      } finally {
        finished = true;
      }
      await delay(
        Duration(milliseconds: 400 * (1 << attempt) + random.nextInt(150)),
      );
    }
    throw const SourceException('network', 'YouTube is unavailable.');
  }

  String _message(String code) => switch (code) {
    'cancelled' => 'Request cancelled.',
    'restricted' => 'This video is private, region-restricted, or requires an account. Open it in YouTube.',
    'unavailable' => 'This video is no longer available on YouTube.',
    'rate_limit' => 'YouTube is limiting requests. Please try again later.',
    'unsupported_format' =>
      'No supported audio stream is available for this video.',
    'extractor' => 'YouTube extraction is temporarily unavailable. An app update may be needed.',
    'invalid' => 'Invalid YouTube request or response.',
    _ => 'Cannot reach YouTube. Retry or choose phone music in Library.',
  };

  Future<YouTubePage> search(
    String query, {
    String? continuation,
    CancelToken? cancel,
  }) async {
    if (!enabled) {
      throw const SourceException(
        'disabled',
        'YouTube is disabled in Settings.',
      );
    }
    query = query.trim();
    if (query.isEmpty) return const YouTubePage([], null);
    final key = 'youtube:search:$query:${continuation ?? ''}';
    var data = await store.cached(key) as Map?;
    if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
    if (data == null) {
      data = await _call('search', {
        'query': query,
        'continuation': continuation,
      }, cancel: cancel);
      await store.cache(key, data, ttl: const Duration(minutes: 15));
    }
    return YouTubePage(
      (data['tracks'] as List)
          .map((t) => _track(Map<String, dynamic>.from(t as Map)))
          .toList(),
      data['continuation'] as String?,
    );
  }

  Future<Track> metadata(Track reference, {CancelToken? cancel}) async {
    _validate(reference);
    return _track(
      await _call('getMetadata', {
        'videoId': reference.providerId,
      }, cancel: cancel),
    );
  }

  void _validate(Track track) {
    if (track.source != MediaSource.youtube ||
        !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(track.providerId)) {
      throw const SourceException(
        'invalid',
        'Invalid YouTube video reference.',
      );
    }
  }

  Future<ResolvedTrack> resolve(
    Track reference, {
    CancelToken? cancel,
    bool alternative = false,
  }) async {
    _validate(reference);
    final data = await _call('resolveAudio', {
      'videoId': reference.providerId,
      'quality': quality.name,
      'alternative': alternative,
    }, cancel: cancel);
    final uri = Uri.tryParse(data['url'] as String? ?? '');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const SourceException(
        'invalid',
        'YouTube returned an invalid audio stream.',
      );
    }
    final expires = (data['expiresAt'] as num?)?.toInt();
    final stream = ResolvedStream(
      uri: uri,
      headers: Map<String, String>.from(data['headers'] as Map? ?? {}),
      mimeType: data['mimeType'] as String?,
      codec: data['codec'] as String?,
      expiresAt: expires == null
          ? now().add(const Duration(minutes: 5))
          : DateTime.fromMillisecondsSinceEpoch(expires),
    );
    if (!stream.freshAt(now())) {
      throw const SourceException(
        'expired',
        'YouTube returned an expired stream. Please retry.',
      );
    }
    return ResolvedTrack(
      _track(Map<String, dynamic>.from(data['track'] as Map)),
      stream,
    );
  }

  Track _track(Map<String, dynamic> j) {
    final id = j['videoId'] as String;
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
      throw const SourceException(
        'invalid',
        'Invalid YouTube video reference.',
      );
    }
    return Track(
      id: 'youtube:$id',
      title: j['title'] as String? ?? 'YouTube video',
      artist: j['uploader'] as String? ?? 'Unknown uploader',
      uri: 'https://www.youtube.com/watch?v=$id',
      artwork: j['artwork'] as String?,
      artistId: j['uploaderUrl'] as String?,
      durationMs: (j['durationMs'] as num? ?? 0).toInt(),
      source: MediaSource.youtube,
      streamable: j['streamable'] != false,
    );
  }
}
