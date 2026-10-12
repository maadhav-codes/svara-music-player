import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'track.dart';
import 'memory_cache.dart';

class ArtworkCache {
  static final _items = MemoryCache<String, Uint8List>(
    capacity: 64,
    ttl: const Duration(hours: 6),
    maxWeight: 8 * 1024 * 1024,
    weightOf: (bytes) => bytes.length,
  );
  static final _pending = <String, Future<Uint8List?>>{};
  static final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );
  static Future<Uint8List?> load(Track track, WidgetRef ref) async {
    final key = track.online ? track.artwork : '${track.uri}:${track.modified}';
    if (key == null) return null;
    final cached = _items.get(key);
    if (cached != null) return cached;
    if (_pending.containsKey(key)) return _pending[key];
    final repository = ref.read(libraryRepositoryProvider);
    final task = () async {
      try {
        Uint8List? bytes;
        if (track.online) {
          final response = await _dio.get<ResponseBody>(
            key,
            options: Options(responseType: ResponseType.stream),
          );
          final builder = BytesBuilder(copy: false);
          await for (final chunk in response.data!.stream) {
            builder.add(chunk);
            if (builder.length > 2 * 1024 * 1024) return null;
          }
          bytes = builder.takeBytes();
        } else {
          bytes = await repository.artwork(track.uri);
        }
        if (bytes == null || bytes.length > 2 * 1024 * 1024) return null;
        _items.put(key, bytes);
        return bytes;
      } catch (_) {
        return null;
      }
    }();
    _pending[key] = task;
    try {
      return await task;
    } finally {
      _pending.remove(key);
    }
  }
}

class TrackArt extends ConsumerStatefulWidget {
  const TrackArt(this.track, {this.size = 52, super.key});
  final Track track;
  final double size;
  @override
  ConsumerState<TrackArt> createState() => _TrackArtState();
}

class _TrackArtState extends ConsumerState<TrackArt> {
  late Future<Uint8List?> _image;
  @override
  void initState() {
    super.initState();
    _image = ArtworkCache.load(widget.track, ref);
  }

  @override
  void didUpdateWidget(TrackArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id ||
        oldWidget.track.modified != widget.track.modified) {
      _image = ArtworkCache.load(widget.track, ref);
    }
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: SizedBox(
      width: widget.size,
      height: widget.size,
      child: FutureBuilder<Uint8List?>(
        future: _image,
        builder: (context, snapshot) => snapshot.data == null
            ? ColoredBox(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Icon(
                  Icons.music_note_rounded,
                  size: widget.size / 2,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              )
            : Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                cacheWidth:
                    (widget.size * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                errorBuilder: (_, e, s) => const Icon(Icons.music_note),
              ),
      ),
    ),
  );
}
