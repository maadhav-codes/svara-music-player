import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:svara/core/store.dart';
import 'package:svara/core/track.dart';
import 'package:svara/features/player/svara_handler.dart';

class MemoryPlayer extends AudioPlayer {
  MemoryPlayer()
    : super(handleInterruptions: false, handleAudioSessionActivation: false);
  final indices = StreamController<int?>.broadcast(sync: true);
  final playingEvents = StreamController<bool>.broadcast(sync: true);
  bool isPlaying = false;
  int? index;
  Duration at = Duration.zero;
  bool fail = false;
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
  Stream<PlayerException> get errorStream => const Stream.empty();
  @override
  bool get playing => isPlaying;
  @override
  int? get currentIndex => index;
  @override
  Duration get position => at;
  @override
  Duration get bufferedPosition => at;
  @override
  ProcessingState get processingState => ProcessingState.ready;
  @override
  bool get shuffleModeEnabled => shuffled;
  @override
  LoopMode get loopMode => loop;
  @override
  bool get hasNext => index != null && index! + 1 < count;
  @override
  bool get hasPrevious => index != null && index! > 0;
  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    loads++;
    if (fail) throw StateError('Removed file');
    count = sources.length;
    index = initialIndex ?? 0;
    at = initialPosition ?? Duration.zero;
    indices.add(index);
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
    expect(player.index, 1);
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
    expect(player.index, 1);
    expect(player.playing, true);
  });
  test(
    'sleep timer pauses and repeat/shuffle modes reach shared player',
    () async {
      await handler.restore();
      await handler.setQueue([t('a')]);
      await handler.setRepeatMode(AudioServiceRepeatMode.one);
      expect(player.loopMode, LoopMode.one);
      await handler.setShuffleMode(AudioServiceShuffleMode.all);
      expect(player.shuffleModeEnabled, true);
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
}
