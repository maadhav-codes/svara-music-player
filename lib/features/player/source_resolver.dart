import 'package:dio/dio.dart';

import '../../core/media_source.dart';
import '../../core/track.dart';
import '../discovery/audius_repository.dart';
import '../discovery/youtube_repository.dart';

class ResolvedTrack {
  const ResolvedTrack(this.track, this.stream);
  final Track track;
  final ResolvedStream stream;
}

typedef ResolveTrack = Future<ResolvedTrack> Function(
  Track track, {
  CancelToken? cancel,
  bool alternative,
});

class SourceResolver {
  SourceResolver({required this.audius, required this.youtube});
  final AudiusRepository audius;
  final YouTubeRepository youtube;
  Future<ResolvedTrack> resolve(
    Track reference, {
    CancelToken? cancel,
    bool alternative = false,
  }) async {
    if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
    switch (reference.source) {
      case MediaSource.local:
        return ResolvedTrack(
          reference,
          ResolvedStream(uri: Uri.parse(reference.uri)),
        );
      case MediaSource.audius:
        final track = await audius.track(reference, cancel: cancel);
        if (!track.streamable) {
          throw const SourceException(
            'restricted',
            'This Audius track is not publicly streamable.',
          );
        }
        return ResolvedTrack(track, ResolvedStream(uri: Uri.parse(track.uri)));
      case MediaSource.youtube:
        return youtube.resolve(
          reference,
          cancel: cancel,
          alternative: alternative,
        );
    }
  }
}
