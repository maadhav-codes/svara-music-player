import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/store.dart';
import 'package:svara/core/track.dart';
import 'package:svara/features/player/svara_handler.dart';
import 'package:svara/core/resolved_track.dart';
import 'package:svara/core/media_source.dart';
import 'package:dio/dio.dart';

class MemoryPlayer extends AudioPlayer {
  MemoryPlayer()
    : super(handleInterruptions: false, handleAudioSessionActivation: false);
  final indices = StreamController<int?>.broadcast(sync: true);
  final playingEvents = StreamController<bool>.broadcast(sync: true);
  final states = StreamController<ProcessingState>.broadcast(sync: true);
  final failures = StreamController<PlayerException>.broadcast(sync: true);
  ProcessingState state = ProcessingState.ready;
  AudioSource? lastSource;
  bool isPlaying = false;
  int? index;
  Duration at = Duration.zero;
  bool fail = false;
  Object? loadError;
  int loads = 0, count = 0;
  LoopMode loop = LoopMode.off;
  bool shuffled = false;
  @override
  Stream<int?> get currentIndexStream => indices.stream;
  @override
  Stream<bool> get playingStream => playingEvents.stream;
  @override
  Stream<PlaybackEvent> get playbackEventStream => const Stream.empty();
  @override
  Stream<PlayerException> get errorStream => failures.stream;
  @override
  Stream<ProcessingState> get processingStateStream => states.stream;
  @override
  bool get playing => isPlaying;
  @override
  int? get currentIndex => index;
  @override
  Duration get position => at;
  @override
  Duration get bufferedPosition => at;
  @override
  ProcessingState get processingState => state;
  @override
  bool get shuffleModeEnabled => shuffled;
  @override
  LoopMode get loopMode => loop;
  @override
  bool get hasNext => index != null && index! + 1 < count;
  @override
  bool get hasPrevious => index != null && index! > 0;
  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    loads++;
    if (fail) throw loadError ?? StateError('Removed file');
    lastSource = source;
    count = 1;
    index = initialIndex ?? 0;
    at = initialPosition ?? Duration.zero;
    indices.add(index);
    state = ProcessingState.ready;
    states.add(state);
    return const Duration(minutes: 3);
  }

  @override
  Future<void> play() async {
    isPlaying = true;
    playingEvents.add(true);
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    playingEvents.add(false);
  }

  @override
  Future<void> stop() async => pause();
  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (index != null) this.index = index;
    at = position ?? Duration.zero;
    indices.add(this.index);
  }

  @override
  Future<void> seekToNext() => seek(Duration.zero, index: index! + 1);
  @override
  Future<void> seekToPrevious() => seek(Duration.zero, index: index! - 1);
  @override
  Future<void> setLoopMode(LoopMode mode) async {
    loop = mode;
  }

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {
    shuffled = enabled;
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    await indices.close();
    await playingEvents.close();
    await states.close();
    await failures.close();
  }

  void complete() {
    state = ProcessingState.completed;
    states.add(state);
  }
}

Track t(String id) => Track(
  id: id,
  title: id,
  artist: 'A',
  uri: 'content://media/external/audio/media/$id',
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
  });
  late Store store;
  late MemoryPlayer player;
  late SvaraHandler handler;
  setUp(() async {
    store = await Store.open(path: inMemoryDatabasePath);
    player = MemoryPlayer();
    handler = SvaraHandler(store, audioPlayer: player);
  });
  tearDown(() async {
    await handler.dispose();
    await Future<void>.delayed(Duration.zero);
    await store.db.close();
  });
  test('restore publishes last queue and position paused without loading any stream', () async {
    await store.write('playback', {
      'tracks': [t('a').toJson(), t('b').toJson()],
      'index': 1,
      'position': 30000,
    });
    await handler.restore();
    expect(player.loads, 0);
    expect(player.playing, false);
    expect(handler.mediaItem.value?.id, 'b');
    expect(handler.position.inSeconds, 30);
    await handler.play();
    expect(player.loads, 1);
    expect(handler.activeIndex, 1);
    expect(player.index, 0);
    expect(player.at.inSeconds, 30);
    expect(player.playing, true);
    await handler.pause();
    expect(player.playing, false);
  });
  test(
    'queue reorder and removal preserve active occurrence and seek position',
    () async {
      await handler.restore();
      await handler.setQueue(
        [t('a'), t('b'), t('a'), t('c')],
        index: 2,
        position: const Duration(seconds: 42),
        start: false,
      );
      await handler.reorder(0, 4);
      expect(handler.tracks.map((t) => t.id), ['b', 'a', 'c', 'a']);
      expect(handler.activeIndex, 1);
      expect(player.at.inSeconds, 42);
      expect(player.playing, false);
      await handler.remove(0);
      expect(handler.activeIndex, 0);
      expect(player.at.inSeconds, 42);
      await handler.remove(0);
      expect(handler.activeIndex, 0);
      expect(player.at, Duration.zero);
    },
  );
  test('failed stream or removed file preserves queue and can retry', () async {
    await handler.restore();
    player.fail = true;
    final message = handler.errors.stream.first;
    await handler.setQueue([t('a'), t('b')], index: 1);
    expect(await message, contains('queue is preserved'));
    expect(handler.tracks.length, 2);
    expect(player.playing, false);
    player.fail = false;
    await handler.play();
    expect(handler.activeIndex, 1);
    expect(player.playing, true);
  });
  test(
    'sleep timer pauses and logical repeat/shuffle modes are published',
    () async {
      await handler.restore();
      await handler.setQueue([t('a')]);
      await handler.setRepeatMode(AudioServiceRepeatMode.one);
      expect(handler.repeatMode, AudioServiceRepeatMode.one);
      expect(player.loopMode, LoopMode.off);
      await handler.setShuffleMode(AudioServiceShuffleMode.all);
      expect(handler.shuffleEnabled, true);
      handler.sleepFor(const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(player.playing, false);
      expect(handler.sleepUntil, null);
    },
  );
  test('large queue window includes selected song and is bounded', () {
    final tracks = List.generate(1200, (i) => t('$i'));
    final window = boundedQueue(tracks, 800);
    expect(window.$1.length, 400);
    expect(window.$1[window.$2].id, '800');
    expect(boundedQueue(tracks, 10).$1.length, 500);
  });

  Track remote(String id) => Track(
    id: 'youtube:$id',
    title: id,
    artist: 'Uploader',
    uri: 'https://www.youtube.com/watch?v=$id',
    source: MediaSource.youtube,
  );
  ResolvedTrack resolved(Track track, {DateTime? expiry}) => ResolvedTrack(
    track,
    ResolvedStream(
      uri: Uri.parse('https://media.example/audio?secret=temporary'),
      expiresAt: expiry,
    ),
  );
  Future<void> replace(ResolveTrack resolver) async {
    await handler.dispose();
    player = MemoryPlayer();
    handler = SvaraHandler(
      store,
      audioPlayer: player,
      resolveYouTube: resolver,
    );
    await handler.restore();
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 30));

  test('resolves only active item; every skip resolves before loading and saves IDs only', () async {
    final requests = <String>[];
    await replace((track, {cancel, alternative = false}) async {
      requests.add(track.id);
      return resolved(track);
    });
    await handler.setQueue([remote('aaaaaaaaaaa'), remote('bbbbbbbbbbb')]);
    expect(requests, ['youtube:aaaaaaaaaaa']);
    expect(player.count, 1);
    await handler.skipToNext();
    expect(requests, ['youtube:aaaaaaaaaaa', 'youtube:bbbbbbbbbbb']);
    expect(handler.playbackState.value.queueIndex, 1);
    expect(player.index, 0);
    await handler.save();
    final data = (await store.read('playback')).toString();
    expect(data, isNot(contains('secret')));
    expect(data, contains('youtube:bbbbbbbbbbb'));
  });

  test(
    'late extraction cannot replace a newer queue or start stale audio',
    () async {
      final first = Completer<ResolvedTrack>();
      CancelToken? firstToken;
      await replace((track, {cancel, alternative = false}) {
        if (track.id.endsWith('aaaaaaaaaaa')) {
          firstToken = cancel;
          return first.future;
        }
        return Future.value(resolved(track));
      });
      final pending = handler.setQueue([remote('aaaaaaaaaaa')]);
      await settle();
      await handler.setQueue([remote('bbbbbbbbbbb')], start: false);
      first.complete(resolved(remote('aaaaaaaaaaa')));
      await pending;
      expect(firstToken!.isCancelled, true);
      expect(handler.current!.id, 'youtube:bbbbbbbbbbb');
      expect(player.loads, 1);
      expect(player.playing, false);
    },
  );

  test(
    'pause and sleep during extraction prevent delayed automatic playback',
    () async {
      final pending = Completer<ResolvedTrack>();
      await replace((track, {cancel, alternative = false}) => pending.future);
      final load = handler.setQueue([remote('aaaaaaaaaaa')]);
      await settle();
      handler.sleepFor(const Duration(milliseconds: 5));
      await settle();
      pending.complete(resolved(remote('aaaaaaaaaaa')));
      await load;
      expect(player.playing, false);
      expect(handler.playbackState.value.playing, false);
    },
  );

  test(
    'repeat one and repeat all re-resolve online audio on completion',
    () async {
      final requests = <String>[];
      await replace((track, {cancel, alternative = false}) async {
        requests.add(track.id);
        return resolved(track);
      });
      await handler.setQueue([remote('aaaaaaaaaaa'), remote('bbbbbbbbbbb')]);
      await handler.setRepeatMode(AudioServiceRepeatMode.one);
      player.complete();
      await settle();
      expect(requests.length, 2);
      expect(handler.activeIndex, 0);
      await handler.setRepeatMode(AudioServiceRepeatMode.all);
      await handler.skipToQueueItem(1);
      player.complete();
      await settle();
      expect(handler.activeIndex, 0);
      expect(requests.last, 'youtube:aaaaaaaaaaa');
    },
  );

  test(
    'stream failure refreshes once, then preserves queue and position paused',
    () async {
      var calls = 0;
      await replace((track, {cancel, alternative = false}) async {
        calls++;
        return resolved(track);
      });
      await handler.setQueue([remote('aaaaaaaaaaa')]);
      player.at = const Duration(seconds: 20);
      player.failures.add(PlayerException(403, 'URL must not leak', 0));
      await settle();
      expect(calls, 2);
      expect(player.at.inSeconds, 20);
      final message = handler.errors.stream.first;
      player.failures.add(PlayerException(403, 'URL must not leak', 0));
      expect(await message, contains('queue is preserved'));
      expect(calls, 2);
      expect(player.playing, false);
      expect(handler.position.inSeconds, 20);
    },
  );

  test(
    'decoder failure during loading requests one alternative format',
    () async {
      final alternatives = <bool>[];
      await replace((track, {cancel, alternative = false}) async {
        alternatives.add(alternative);
        player.fail = !alternative;
        player.loadError = PlayerException(0, 'decoder failed', 0);
        return resolved(track);
      });
      await handler.setQueue([remote('aaaaaaaaaaa')]);
      expect(alternatives, [false, true]);
      expect(player.loads, 2);
      expect(player.playing, true);
    },
  );

  test(
    'shuffle visits each occurrence, including duplicate IDs, once per cycle',
    () async {
      await handler.restore();
      await handler.setQueue([t('a'), t('a'), t('b'), t('c')]);
      await handler.setShuffleMode(AudioServiceShuffleMode.all);
      final seen = <int>{handler.activeIndex};
      for (var i = 0; i < 3; i++) {
        await handler.skipToNext();
        seen.add(handler.activeIndex);
      }
      expect(seen.length, 4);
      final last = handler.activeIndex;
      await handler.skipToNext();
      expect(handler.activeIndex, last);
      await handler.setShuffleMode(AudioServiceShuffleMode.none);
      await handler.skipToQueueItem(1);
      await handler.skipToPrevious();
      expect(handler.activeIndex, 0);
    },
  );
}
