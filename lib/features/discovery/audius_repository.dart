import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/store.dart';
import '../../core/track.dart';

class AudiusConfig {
  static const baseUrl = String.fromEnvironment(
    'AUDIUS_BASE_URL',
    defaultValue: 'https://api.audius.co',
  );
  static const apiKey = String.fromEnvironment('AUDIUS_API_KEY');
}

class DiscoveryException implements Exception {
  const DiscoveryException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AudiusRepository {
  AudiusRepository(
    this.store, {
    Dio? client,
    Future<void> Function(Duration)? delay,
  }) : dio =
           client ??
           Dio(
             BaseOptions(
               baseUrl: AudiusConfig.baseUrl,
               connectTimeout: const Duration(seconds: 8),
               receiveTimeout: const Duration(seconds: 12),
             ),
           ),
       delay = delay ?? Future<void>.delayed;
  final Store store;
  final Dio dio;
  final Future<void> Function(Duration) delay;
  Future<dynamic> get(
    String path,
    Map<String, dynamic> params, {
    CancelToken? cancel,
  }) async {
    final key = '$path:$params';
    final cached = await store.cached(key);
    if (cached != null) return cached;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await dio.get<Map<String, dynamic>>(
          path,
          queryParameters: {
            ...params,
            'app_name': 'Svara',
            if (AudiusConfig.apiKey.isNotEmpty) 'api_key': AudiusConfig.apiKey,
          },
          cancelToken: cancel,
        );
        final data = response.data?['data'];
        if (data == null) {
          throw const DiscoveryException(
            'Audius returned an invalid response.',
          );
        }
        await store.cache(key, data);
        return data;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        final status = e.response?.statusCode;
        final retry =
            status == 429 ||
            (status != null && status >= 500) ||
            status == null;
        if (!retry || attempt == 2) {
          throw DiscoveryException(switch (status) {
            429 => 'Audius is busy. Please try again later.',
            401 ||
            403 => 'Audius access is restricted. Check the API configuration.',
            404 => 'This music is no longer available on Audius.',
            _ => 'Cannot reach Audius. Your phone music is still available in Library.',
          });
        }
        // Bound Retry-After to avoid keeping a request alive indefinitely.
        final seconds = int.tryParse(
          e.response?.headers.value('retry-after') ?? '',
        );
        await delay(
          Duration(
            milliseconds: seconds != null
                ? seconds.clamp(1, 4) * 1000
                : 400 * (1 << attempt),
          ),
        );
        if (cancel?.isCancelled ?? false) {
          throw cancel!.cancelError!;
        }
      }
    }
    throw const DiscoveryException('Audius is unavailable.');
  }

  Future<List<Track>> tracks({
    String query = '',
    String? genre,
    String? time,
    int offset = 0,
    CancelToken? cancel,
  }) async {
    final data = await get(
      query.isEmpty ? '/v1/tracks/trending' : '/v1/tracks/search',
      {
        'limit': 30,
        'offset': offset,
        if (query.isNotEmpty) 'query': query,
        if (query.isEmpty && genre != null) 'genre': genre,
        if (query.isEmpty) 'time': time ?? 'week',
      },
      cancel: cancel,
    );
    return (data as List)
        .map((item) => _track(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<Track> track(Track reference, {CancelToken? cancel}) async => _track(
    Map<String, dynamic>.from(
      await get('/v1/tracks/${reference.providerId}', {}, cancel: cancel),
    ),
  );
  Track _track(Map<String, dynamic> j) {
    final user = Map<String, dynamic>.from(j['user'] as Map? ?? {});
    final art = j['artwork'] as Map?;
    final id = j['id'].toString();
    return Track(
      id: 'audius:$id',
      title: j['title'] as String? ?? 'Untitled',
      artist: user['name'] as String? ?? 'Unknown artist',
      artistId: user['id']?.toString(),
      uri: Uri.parse('${AudiusConfig.baseUrl}/v1/tracks/$id/stream')
          .replace(
            queryParameters: {
              'app_name': 'Svara',
              if (AudiusConfig.apiKey.isNotEmpty)
                'api_key': AudiusConfig.apiKey,
            },
          )
          .toString(),
      durationMs: ((j['duration'] as num? ?? 0) * 1000).toInt(),
      artwork: art?['480x480'] as String? ?? art?['150x150'] as String?,
      online: true,
      streamable:
          j['is_streamable'] != false &&
          j['is_stream_gated'] != true &&
          j['is_unlisted'] != true,
    );
  }

  Future<Map<String, dynamic>> artist(String id) async =>
      Map<String, dynamic>.from(await get('/v1/users/$id', {}));
}
