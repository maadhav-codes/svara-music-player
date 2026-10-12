import 'package:dio/dio.dart';

import 'media_source.dart';
import 'track.dart';

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
