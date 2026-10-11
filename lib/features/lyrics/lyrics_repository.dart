import 'dart:io' show HttpDate;

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../../core/track.dart';
import 'lyrics.dart';

class LyricsException implements Exception {
  const LyricsException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LyricsRepository {
  LyricsRepository({
    Dio? dio,
    this.channel = const MethodChannel('app.svara/media'),
  }) : dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: 'https://lrclib.net/api',
               connectTimeout: const Duration(seconds: 8),
               receiveTimeout: const Duration(seconds: 12),
               headers: {
                 'User-Agent': 'Svara/2.0 (https://github.com/maadhav-codes/svara-music-player)',
                 'Accept': 'application/json',
               },
             ),
           );
  final Dio dio;
  final MethodChannel channel;
  final _cache = <String, ({DateTime expires, Lyrics lyrics})>{};
  DateTime? _retryAfter;
  static const maxText = 256 * 1024;
  Future<bool> chooseFolder(Track track) async =>
      await channel.invokeMethod<bool>('chooseLyricsFolder', {
        'uri': track.uri,
        'folder': track.folder,
      }) ??
      false;
  Future<Lyrics?> load(
    Track track, {
    CancelToken? cancelToken,
    bool refresh = false,
  }) async {
    if (!track.online) {
      try {
        final text = await channel.invokeMethod<String>('readLocalLyrics', {
          'uri': track.uri,
          'folder': track.folder,
        });
        if (text != null && text.length <= maxText) {
          final local = Lyrics.parse(text, source: 'Local .lrc');
          if (!local.empty) return local;
        }
      } on PlatformException {
        /* Missing/revoked folder access still allows online lookup. */
      }
    }
    if (cancelToken?.isCancelled == true) {
      throw cancelToken!.cancelError!;
    }
    final key =
        '${track.title}\u0000${track.artist}\u0000${track.album}\u0000${track.durationMs}';
    final cached = _cache.remove(key);
    if (!refresh && cached != null && cached.expires.isAfter(DateTime.now())) {
      _cache[key] = cached;
      return cached.lyrics;
    }
    if (track.title.trim().isEmpty || track.artist.trim().isEmpty) return null;
    if (_retryAfter?.isAfter(DateTime.now()) == true) {
      throw const LyricsException('LRCLIB is busy. Please try again later.');
    }
    try {
      // Exact title/artist first; duration and album disambiguate recordings.
      final response = await dio.get<dynamic>(
        '/get',
        queryParameters: {
          'track_name': track.title,
          'artist_name': track.artist,
          if (track.album.isNotEmpty) 'album_name': track.album,
          if (track.durationMs >= 1000 && track.durationMs <= 3600000)
            'duration': track.durationMs / 1000,
        },
        cancelToken: cancelToken,
      );
      if (response.data is! Map) {
        throw const LyricsException(
          'The lyrics service returned an invalid response.',
        );
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      final duration = data['duration'];
      if (track.durationMs > 0 &&
          duration is num &&
          (duration * 1000 - track.durationMs).abs() > 2000) {
        return null;
      }
      final synced = data['syncedLyrics'];
      final plain = data['plainLyrics'];
      if ((synced != null && synced is! String) ||
          (plain != null && plain is! String) ||
          (synced is String && synced.length > maxText) ||
          (plain is String && plain.length > maxText) ||
          ((synced is String ? synced.length : 0) +
                  (plain is String ? plain.length : 0) >
              maxText)) {
        throw const LyricsException('The lyrics response could not be read.');
      }
      final lyrics = Lyrics.parse(
        synced as String? ?? '',
        plain: plain as String? ?? '',
        instrumental: data['instrumental'] == true,
        source: 'LRCLIB',
      );
      if (lyrics.empty) return null;
      _cache[key] = (
        expires: DateTime.now().add(const Duration(hours: 6)),
        lyrics: lyrics,
      );
      while (_cache.length > 20) {
        _cache.remove(_cache.keys.first);
      }
      return lyrics;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      if (e.response?.statusCode == 404) return null;
      if (e.response?.statusCode == 429) {
        final header = e.response?.headers.value('retry-after');
        final seconds = int.tryParse(header ?? '');
        DateTime? date;
        try {
          if (header != null && seconds == null) {
            date = HttpDate.parse(header);
          }
        } catch (_) {}
        _retryAfter =
            date ??
            DateTime.now().add(
              Duration(seconds: seconds == null || seconds < 1 ? 60 : seconds),
            );
        throw const LyricsException('LRCLIB is busy. Please try again later.');
      }
      throw const LyricsException(
        'Lyrics are unavailable. Check your connection or use a local .lrc file.',
      );
    }
  }

  void dispose() => dio.close(force: true);
}
