enum MediaSource {
  local('Phone storage'),
  audius('Audius'),
  youtube('YouTube');

  const MediaSource(this.label);
  final String label;
}

enum StreamQuality { dataSaver, standard, high }

/// Ephemeral playback data. Never serialize this into queues or playlists.
class ResolvedStream {
  ResolvedStream({
    required this.uri,
    Map<String, String> headers = const {},
    this.mimeType,
    this.codec,
    this.expiresAt,
  }) : headers = Map.unmodifiable(headers);
  final Uri uri;
  final Map<String, String> headers;
  final String? mimeType, codec;
  final DateTime? expiresAt;
  bool freshAt(DateTime now) =>
      expiresAt == null ||
      expiresAt!.isAfter(now.add(const Duration(seconds: 30)));
}

class SourceException implements Exception {
  const SourceException(this.code, this.message, {this.retryAfter});
  final String code, message;
  final Duration? retryAfter;
  bool get transient => const {
    'network',
    'timeout',
    'server',
    'rate_limit',
    'busy',
  }.contains(code);
  @override
  String toString() => message;
}
