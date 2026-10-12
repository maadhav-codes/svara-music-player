import 'package:dio/dio.dart';

import '../../core/media_source.dart';
import '../../core/track.dart';
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
  SourceResolver({required this.youtube});
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
      case MediaSource.youtube:
        return youtube.resolve(
          reference,
          cancel: cancel,
          alternative: alternative,
        );
    }
  }
}
