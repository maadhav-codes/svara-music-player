import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:dio/dio.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/media_source.dart';
import '../../core/store.dart';
import '../../core/track.dart';
import '../../core/resolved_track.dart';
import '../discovery/youtube_repository.dart';

/// Owns the durable logical queue. The engine receives only the selected source;
/// queue indices are never inferred from the engine's single-source index.
class SvaraHandler extends BaseAudioHandler with SeekHandler {
  SvaraHandler(
    this.store, {
    AudioPlayer? audioPlayer,
    ResolveTrack? resolveYouTube,
    Random? random,
  }) : player =
           audioPlayer ??
           AudioPlayer(
             handleInterruptions: false,
             useProxyForRequestHeaders: false,
           ),
       resolveYouTube = resolveYouTube ?? YouTubeRepository(store).resolve,
       random = random ?? Random() {
    _subscriptions.add(player.playbackEventStream.listen((_) => _broadcast()));
    _subscriptions.add(
      player.errorStream.listen((e) => unawaited(_failure(e))),
    );
    _subscriptions.add(
      player.processingStateStream.listen((state) {
        _broadcast();
        if (state == ProcessingState.completed &&
            _loaded &&
            _wantsPlay &&
            !_completing) {
          _completing = true;
          unawaited(_complete().whenComplete(() => _completing = false));
        }
      }),
    );
    _subscriptions.add(
      player.playingStream.listen((playing) {
        _broadcast();
        if (playing && current != null) _background(store.played(current!.id));
        _background(save());
      }),
    );
    _persist = Timer.periodic(const Duration(seconds: 15), (_) {
      if (player.playing) _background(save());
    });
  }
  final Store store;
  final AudioPlayer player;
  final ResolveTrack resolveYouTube;
  final Random random;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _pending = <Future<void>>{};
  final errors = StreamController<String>.broadcast();
  List<Track> tracks = [];
  List<int> _order = [];
  int _index = 0, _loadGeneration = 0;
  Duration _position = Duration.zero;
  bool _initialized = false, _loaded = false, _loading = false;
  bool _disposed = false,
      _wantsPlay = false,
      _completing = false,
      _recovering = false;
  bool _resumeAfterInterruption = false;
  bool shuffleEnabled = false;
  AudioServiceRepeatMode repeatMode = AudioServiceRepeatMode.none;
  CancelToken? _cancel;
  ResolvedStream? _stream;
  int _automaticRetries = 0;
  Timer? _persist, _sleep;
  DateTime? sleepUntil;
  int get activeIndex => _index;
  Duration get position => _loaded ? player.position : _position;
  Track? get current =>
      tracks.isNotEmpty && _index < tracks.length ? tracks[_index] : null;

  void _background(Future<void> task) {
    late Future<void> tracked;
    tracked = task
        .catchError((Object e) {
          if (!errors.isClosed) {
            errors.add(
              'Could not save playback data. Check available device storage.',
            );
          }
        })
        .whenComplete(() => _pending.remove(tracked));
    _pending.add(tracked);
  }

  Future<void> initialize() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _subscriptions.add(
      session.becomingNoisyEventStream.listen((_) {
        _resumeAfterInterruption = false;
        unawaited(pause());
      }),
    );
    _subscriptions.add(
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          _resumeAfterInterruption = _wantsPlay;
          if (event.type == AudioInterruptionType.duck) {
            unawaited(player.setVolume(.25));
          } else {
            unawaited(_pauseEngine());
          }
        } else {
          unawaited(player.setVolume(1));
          if (event.type == AudioInterruptionType.pause &&
              _resumeAfterInterruption) {
            unawaited(play());
          }
          _resumeAfterInterruption = false;
        }
      }),
    );
    await restore();
  }

  Future<void> restore() async {
    final saved = await store.read('playback') as Map?;
    if (saved != null) {
      tracks = (saved['tracks'] as List)
          .map((j) => Track.fromJson(Map<String, dynamic>.from(j as Map)))
          .toList();
      _index = (saved['index'] as int? ?? 0).clamp(
        0,
        tracks.isEmpty ? 0 : tracks.length - 1,
      );
      _position = Duration(milliseconds: saved['position'] as int? ?? 0);
      shuffleEnabled = saved['shuffle'] == true;
      repeatMode =
          AudioServiceRepeatMode.values
              .where((m) => m.name == saved['repeat'])
              .firstOrNull ??
          AudioServiceRepeatMode.none;
    }
    _rebuildOrder();
    _publishQueue();
    _initialized = true;
    _broadcast();
  }

  void _rebuildOrder() {
    _order = List.generate(tracks.length, (i) => i);
    if (shuffleEnabled && tracks.isNotEmpty) {
      _order.remove(_index);
      _order.shuffle(random);
      _order.insert(0, _index);
    }
  }

  void _publishQueue() {
    queue.add(tracks.map(_item).toList());
    mediaItem.add(current == null ? null : _item(current!));
  }

  MediaItem _item(Track t) => MediaItem(
    id: t.id,
    title: t.title,
    artist: t.artist,
    album: t.online ? t.source.label : t.album,
    duration: t.durationMs > 0 ? Duration(milliseconds: t.durationMs) : null,
    // Avoid audio_service's persistent remote artwork cache.
    artUri: t.online || t.artwork == null ? null : Uri.tryParse(t.artwork!),
    extras: {'source': t.source.name, 'sourceUrl': t.sourceUrl},
  );

  Future<void> setQueue(
    List<Track> next, {
    int index = 0,
    Duration position = Duration.zero,
    bool start = true,
  }) async {
    if (_disposed) return;
    if (next.isEmpty) {
      ++_loadGeneration;
      _cancel?.cancel();
      _wantsPlay = false;
      _loaded = false;
      _loading = false;
      _stream = null;
      tracks = [];
      _index = 0;
      _position = Duration.zero;
      _order = [];
      await player.stop();
      _publishQueue();
      _broadcast();
      await save();
      return;
    }
    final bounded = boundedQueue(next, index.clamp(0, next.length - 1));
    if (bounded.$1.isEmpty) {
      errors.add('No playable tracks in this selection.');
      return;
    }
    tracks = List.of(bounded.$1);
    _index = bounded.$2;
    _position = position;
    _wantsPlay = start;
    _automaticRetries = 0;
    _rebuildOrder();
    _publishQueue();
    await _load(position: position);
  }

  Future<void> _load({
    Duration position = Duration.zero,
    bool alternative = false,
  }) async {
    final reference = current;
    if (reference == null || _disposed) return;
    final generation = ++_loadGeneration;
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    _loaded = false;
    _loading = true;
    _stream = null;
    _position = position;
    _broadcast();
    await player.pause();
    if (generation != _loadGeneration || _disposed) return;
    // A failed resolution must still leave the selected queue available to retry.
    await save();
    try {
      final resolved = reference.source == MediaSource.local
          ? ResolvedTrack(
              reference,
              ResolvedStream(uri: Uri.parse(reference.uri)),
            )
          : await resolveYouTube(
              reference,
              cancel: cancel,
              alternative: alternative,
            );
      if (generation != _loadGeneration || _disposed) return;
      if (!resolved.track.streamable) {
        throw const SourceException(
          'restricted',
          'This track cannot be streamed.',
        );
      }
      if (!resolved.stream.freshAt(DateTime.now())) {
        throw const SourceException('expired', 'Stream expired. Please retry.');
      }
      tracks[_index] = resolved.track;
      _stream = resolved.stream;
      _publishQueue();
      final requestedPosition = _position;
      await player.setAudioSource(
        AudioSource.uri(
          resolved.stream.uri,
          headers: resolved.stream.headers,
          tag: _item(resolved.track),
        ),
        initialPosition: requestedPosition,
      );
      if (generation != _loadGeneration || _disposed) return;
      if (_position != requestedPosition) {
        await player.seek(_position);
        if (generation != _loadGeneration || _disposed) return;
      }
      _loaded = true;
      _loading = false;
      _broadcast();
      await save();
      if (_wantsPlay) _startEngine();
    } catch (e) {
      if (generation != _loadGeneration || _disposed || cancel.isCancelled) {
        return;
      }
      _loading = false;
      _loaded = false;
      if (reference.online &&
          e is PlayerException &&
          _automaticRetries == 0 &&
          _wantsPlay) {
        _automaticRetries++;
        await _load(position: _position, alternative: true);
        return;
      }
      // Exceptions from extractors are already sanitized; engine exceptions may
      // contain signed URLs and must never be displayed or persisted.
      _wantsPlay = false;
      errors.add(e is SourceException ? e.toString() : _playbackMessage);
      _broadcast();
      await save();
    }
  }

  String get _playbackMessage => current?.online == true
      ? '${current!.source.label} playback unavailable. Retry or choose phone music in Library. Your queue is preserved.'
      : 'Playback unavailable. Refresh Library for moved, deleted, or unsupported files. Your queue is preserved.';

  void _startEngine() {
    unawaited(
      player.play().catchError((Object e) {
        unawaited(_failure(e));
      }),
    );
  }

  Future<void> _failure(Object error) async {
    if (_loading || _recovering || _disposed || !_loaded) return;
    _position = player.position;
    _loaded = false;
    if (current?.online == true && _wantsPlay && _automaticRetries == 0) {
      _automaticRetries++;
      _recovering = true;
      try {
        await _load(position: _position, alternative: true);
      } finally {
        _recovering = false;
      }
      return;
    }
    _wantsPlay = false;
    await player.pause();
    if (!errors.isClosed) errors.add(_playbackMessage);
    _broadcast();
    await save();
  }

  Future<void> _complete() async {
    if (repeatMode == AudioServiceRepeatMode.one) {
      await _select(_index);
      return;
    }
    final next = _neighbor(1);
    if (next != null) {
      await _select(next);
    } else {
      _wantsPlay = false;
      await player.pause();
      _broadcast();
      await save();
    }
  }

  int? _neighbor(int direction) {
    if (_order.isEmpty) return null;
    final slot = _order.indexOf(_index) + direction;
    if (slot >= 0 && slot < _order.length) return _order[slot];
    if (repeatMode == AudioServiceRepeatMode.all) {
      return direction > 0 ? _order.first : _order.last;
    }
    return null;
  }

  Future<void> _select(int index) async {
    _index = index;
    _position = Duration.zero;
    _automaticRetries = 0;
    _publishQueue();
    await _load();
  }

  void _broadcast() {
    if (_disposed) return;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          _wantsPlay ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: _loading
            ? AudioProcessingState.loading
            : switch (player.processingState) {
                ProcessingState.idle => AudioProcessingState.idle,
                ProcessingState.loading => AudioProcessingState.loading,
                ProcessingState.buffering => AudioProcessingState.buffering,
                ProcessingState.ready => AudioProcessingState.ready,
                ProcessingState.completed => AudioProcessingState.completed,
              },
        playing: _wantsPlay && (_loaded || _loading),
        updatePosition: position,
        bufferedPosition: _loaded ? player.bufferedPosition : Duration.zero,
        speed: player.speed,
        queueIndex: tracks.isEmpty ? null : _index,
        shuffleMode: shuffleEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        repeatMode: repeatMode,
      ),
    );
  }

  Future<void> save() async {
    if (!_initialized) return;
    await store.write('playback', {
      'tracks': tracks.map((t) => t.toSavedJson()).toList(),
      'index': _index,
      'position': position.inMilliseconds,
      'shuffle': shuffleEnabled,
      'repeat': repeatMode.name,
    });
  }

  @override
  Future<void> play() async {
    if (tracks.isEmpty || _disposed) return;
    _wantsPlay = true;
    if (_loading) {
      _broadcast();
      return;
    }
    _automaticRetries = 0;
    if (!_loaded || (_stream != null && !_stream!.freshAt(DateTime.now()))) {
      final at = position;
      await _load(position: at);
      return;
    }
    if (player.processingState == ProcessingState.completed) {
      await _load();
      return;
    }
    _startEngine();
    _broadcast();
  }

  @override
  Future<void> pause() async {
    // A user pause or sleep timer during a call must cancel focus-gain resume.
    _resumeAfterInterruption = false;
    await _pauseEngine();
  }

  Future<void> _pauseEngine() async {
    _wantsPlay = false;
    await player.pause();
    _broadcast();
    await save();
  }

  @override
  Future<void> seek(Duration position) async {
    final at = position.isNegative ? Duration.zero : position;
    if (_loading) {
      _position = at;
      await save();
      return;
    }
    if (_loaded && (_stream?.freshAt(DateTime.now()) ?? true)) {
      try {
        await player.seek(at);
      } catch (e) {
        await _failure(e);
      }
    } else {
      _position = at;
      if (_loaded) await _load(position: at);
    }
    _broadcast();
    await save();
  }

  @override
  Future<void> skipToNext() async {
    final next = _neighbor(1);
    if (next != null) {
      _wantsPlay = true;
      await _select(next);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    final previous = _neighbor(-1);
    if (previous != null) {
      _wantsPlay = true;
      await _select(previous);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= tracks.length) return;
    _wantsPlay = true;
    await _select(index);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    this.repeatMode = repeatMode == AudioServiceRepeatMode.group
        ? AudioServiceRepeatMode.all
        : repeatMode;
    _broadcast();
    await save();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    shuffleEnabled = shuffleMode != AudioServiceShuffleMode.none;
    _rebuildOrder();
    _broadcast();
    await save();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final selected = reorderedActiveIndex(_index, oldIndex, newIndex);
    final at = position;
    tracks = moveQueueItem(tracks, oldIndex, newIndex);
    _index = selected;
    _rebuildOrder();
    _publishQueue();
    if (_loading) await _load(position: at);
    _broadcast();
    await save();
  }

  Future<void> remove(int index) async {
    if (index < 0 || index >= tracks.length) return;
    final selected = index == _index;
    final wasPlaying = _wantsPlay;
    tracks = List.of(tracks)..removeAt(index);
    if (tracks.isEmpty) {
      await setQueue([]);
      return;
    }
    if (index < _index) _index--;
    if (_index >= tracks.length) _index = tracks.length - 1;
    _rebuildOrder();
    _publishQueue();
    if (selected) {
      _wantsPlay = wasPlaying;
      _automaticRetries = 0;
      await _load();
    } else if (_loading) {
      await _load(position: position);
    }
    _broadcast();
    await save();
  }

  void sleepFor(Duration? duration) {
    _sleep?.cancel();
    sleepUntil = duration == null ? null : DateTime.now().add(duration);
    if (duration != null) {
      _sleep = Timer(duration, () {
        sleepUntil = null;
        unawaited(pause());
      });
    }
  }

  @override
  Future<void> stop() async {
    ++_loadGeneration;
    _cancel?.cancel();
    _loading = false;
    await pause();
    _position = position;
    _loaded = false;
    _stream = null;
    await player.stop();
    _broadcast();
    await save();
    await super.stop();
  }

  Future<void> dispose() async {
    ++_loadGeneration;
    _cancel?.cancel();
    _sleep?.cancel();
    _persist?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await Future.wait(_pending.toList());
    await save();
    _initialized = false;
    _disposed = true;
    await player.dispose();
    await errors.close();
  }
}
