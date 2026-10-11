import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/store.dart';
import '../../core/track.dart';

class SvaraHandler extends BaseAudioHandler with SeekHandler {
  SvaraHandler(this.store, {AudioPlayer? audioPlayer, this.resolveOnline})
    : player =
          audioPlayer ??
          AudioPlayer(useLazyPreparation: true, handleInterruptions: false) {
    _subscriptions.add(
      player.playbackEventStream.listen(
        (_) => _broadcast(),
        onError: (Object e, StackTrace s) => _failure(e),
      ),
    );
    _subscriptions.add(player.errorStream.listen(_failure));
    _subscriptions.add(
      player.currentIndexStream.listen((index) {
        if (index != null && index < tracks.length) {
          mediaItem.add(_item(tracks[index]));
          if (tracks[index].online && tracks[index].title == 'Audius track') {
            _background(_hydrate(index));
          }
          if (player.playing) _background(store.played(tracks[index].id));
          _background(save());
        }
      }),
    );
    _subscriptions.add(
      player.playingStream.listen((playing) {
        if (playing && current != null) _background(store.played(current!.id));
        _broadcast();
        _background(save());
      }),
    );
    _persist = Timer.periodic(const Duration(seconds: 15), (_) {
      if (player.playing) _background(save());
    });
  }
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _pending = <Future<void>>{};
  void _background(Future<void> task) {
    late Future<void> tracked;
    tracked = task
        .catchError((Object e) {
          if (!errors.isClosed) {
            errors.add(
              'Could not save playback data. Please check available device storage.',
            );
          }
        })
        .whenComplete(() => _pending.remove(tracked));
    _pending.add(tracked);
  }

  final Future<Track> Function(Track)? resolveOnline;
  final Store store;
  final AudioPlayer player;
  bool _initialized = false;
  int _loadGeneration = 0;
  int get activeIndex => _loaded ? player.currentIndex ?? 0 : _restoredIndex;
  Duration get position => _loaded ? player.position : _restoredPosition;
  List<Track> tracks = [];
  final errors = StreamController<String>.broadcast();
  Timer? _persist, _sleep;
  DateTime? sleepUntil;
  bool _resumeAfterInterruption = false;
  Track? get current =>
      player.currentIndex != null && player.currentIndex! < tracks.length
      ? tracks[player.currentIndex!]
      : null;
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
          _resumeAfterInterruption = player.playing;
          if (event.type == AudioInterruptionType.duck) {
            unawaited(player.setVolume(.25));
          } else {
            unawaited(pause());
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
      // Publish without loading a network stream during startup.
      queue.add(tracks.map(_item).toList());
      final index = (saved['index'] as int? ?? 0).clamp(
        0,
        tracks.isEmpty ? 0 : tracks.length - 1,
      );
      if (tracks.isNotEmpty) mediaItem.add(_item(tracks[index]));
      _restoredIndex = index;
      _restoredPosition = Duration(
        milliseconds: saved['position'] as int? ?? 0,
      );
    }
    _initialized = true;
    _broadcast();
  }

  int _restoredIndex = 0;
  Duration _restoredPosition = Duration.zero;
  bool _loaded = false;
  Future<void> _hydrate(int index) async {
    if (resolveOnline == null) return;
    final reference = tracks[index];
    try {
      final fresh = await resolveOnline!(reference);
      if (index >= tracks.length || !identical(tracks[index], reference)) {
        return;
      }
      if (!fresh.streamable) {
        errors.add('This Audius track is no longer publicly streamable.');
        await pause();
        return;
      }
      tracks[index] = fresh;
      queue.add(tracks.map(_item).toList());
      if (activeIndex == index) mediaItem.add(_item(fresh));
    } catch (e) {
      if (!errors.isClosed) errors.add(e.toString());
    }
  }

  MediaItem _item(Track t) => MediaItem(
    id: t.id,
    title: t.title,
    artist: t.artist,
    album: t.online ? 'Audius' : t.album,
    duration: Duration(milliseconds: t.durationMs),
    artUri: t.online || t.artwork == null ? null : Uri.tryParse(t.artwork!),
    extras: {'uri': t.uri},
  );
  Future<void> setQueue(
    List<Track> next, {
    int index = 0,
    Duration position = Duration.zero,
    bool start = true,
  }) async {
    final generation = ++_loadGeneration;
    if (next.isEmpty) {
      await player.stop();
      tracks = [];
      queue.add([]);
      mediaItem.add(null);
      _loaded = false;
      await save();
      return;
    }
    index = index.clamp(0, next.length - 1);
    if (next[index].online && resolveOnline != null) {
      try {
        next = List.of(next);
        next[index] = await resolveOnline!(next[index]);
      } catch (e) {
        errors.add(e.toString());
        return;
      }
    }
    if (generation != _loadGeneration) return;
    if (!next[index].streamable) {
      errors.add('This Audius track is restricted and cannot be streamed.');
      return;
    }
    final bounded = boundedQueue(next, index);
    next = bounded.$1;
    index = bounded.$2;
    await player.pause();
    if (generation != _loadGeneration) return;
    _loaded = false;
    tracks = List.of(next);
    queue.add(tracks.map(_item).toList());
    mediaItem.add(_item(tracks[index]));
    _restoredIndex = index;
    _restoredPosition = position;
    try {
      await player.setAudioSources(
        tracks
            .map((t) => AudioSource.uri(Uri.parse(t.uri), tag: _item(t)))
            .toList(),
        initialIndex: index,
        initialPosition: position,
      );
      if (generation != _loadGeneration) return;
      _loaded = true;
      await save();
      if (start) unawaited(play());
    } catch (e) {
      if (generation != _loadGeneration) return;
      _loaded = false;
      _failure(e);
      await save();
    }
  }

  void _failure(Object e) {
    if (_loaded) {
      _restoredIndex = player.currentIndex ?? 0;
      _restoredPosition = player.position;
    }
    _loaded = false;
    unawaited(pause());
    errors.add(
      'Playback unavailable. Check your connection for Audius, or refresh Library for moved, deleted, or unsupported files. Your queue is preserved.',
    );
  }

  void _broadcast() {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          player.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: player.playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: player.currentIndex,
        shuffleMode: player.shuffleModeEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        repeatMode: switch (player.loopMode) {
          LoopMode.off => AudioServiceRepeatMode.none,
          LoopMode.one => AudioServiceRepeatMode.one,
          LoopMode.all => AudioServiceRepeatMode.all,
        },
      ),
    );
  }

  Future<void> save() async {
    if (!_initialized) return;
    await store.write('playback', {
      'tracks': tracks.map((t) => t.toSavedJson()).toList(),
      'index': _loaded ? player.currentIndex ?? 0 : _restoredIndex,
      'position': _loaded
          ? player.position.inMilliseconds
          : _restoredPosition.inMilliseconds,
    });
  }

  @override
  Future<void> play() async {
    if (tracks.isEmpty) return;
    if (!_loaded) {
      await setQueue(
        tracks,
        index: _restoredIndex,
        position: _restoredPosition,
        start: false,
      );
    }
    if (_loaded) {
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero, index: activeIndex);
      }
      unawaited(
        player.play().catchError((Object e) {
          _failure(e);
        }),
      );
    }
  }

  @override
  Future<void> pause() async {
    await player.pause();
    await save();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_loaded) {
      await player.seek(position);
    } else {
      _restoredPosition = position;
    }
    await save();
  }

  @override
  Future<void> skipToNext() async {
    if (!_loaded && activeIndex + 1 < tracks.length) {
      await setQueue(tracks, index: activeIndex + 1);
    } else if (player.hasNext) {
      await player.seekToNext();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (!_loaded && activeIndex > 0) {
      await setQueue(tracks, index: activeIndex - 1);
      return;
    }
    if (position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
    } else if (player.hasPrevious) {
      await player.seekToPrevious();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= tracks.length) return;
    if (!_loaded) {
      await setQueue(tracks, index: index);
    } else if (tracks[index].streamable) {
      await player.seek(Duration.zero, index: index);
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    await player.setLoopMode(switch (repeatMode) {
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all => LoopMode.all,
      _ => LoopMode.off,
    });
    _broadcast();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    await player.setShuffleModeEnabled(
      shuffleMode == AudioServiceShuffleMode.all,
    );
    _broadcast();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final selected = reorderedActiveIndex(activeIndex, oldIndex, newIndex);
    final savedPosition = position;
    final next = moveQueueItem(tracks, oldIndex, newIndex);
    await setQueue(
      next,
      index: selected,
      position: savedPosition,
      start: player.playing,
    );
  }

  Future<void> remove(int index) async {
    final previous = activeIndex;
    final savedPosition = position;
    final next = List<Track>.of(tracks)..removeAt(index);
    final active = previous == index
        ? -1
        : previous > index
        ? previous - 1
        : previous;
    await setQueue(
      next,
      index: next.isEmpty
          ? 0
          : active < 0
          ? index.clamp(0, next.length - 1)
          : active,
      position: active < 0 ? Duration.zero : savedPosition,
      start: player.playing,
    );
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
    await pause();
    await player.stop();
    await super.stop();
  }

  Future<void> dispose() async {
    _sleep?.cancel();
    _persist?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await Future.wait(_pending.toList());
    await save();
    _initialized = false;
    await player.dispose();
    await errors.close();
  }
}
