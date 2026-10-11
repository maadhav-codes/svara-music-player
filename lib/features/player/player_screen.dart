import '../lyrics/lyrics_screen.dart';

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/track.dart';
import '../../core/media_source.dart';
import '../../core/artwork.dart';
import 'svara_handler.dart';

String timeLabel(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
Track? active(SvaraHandler h) => h.current;

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ref.watch(handlerProvider);
    return StreamBuilder<MediaItem?>(
      stream: h.mediaItem,
      builder: (_, snapshot) {
        final t = active(h);
        if (t == null) return const SizedBox();
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const PlayerScreen()),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  TrackArt(t, size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          t.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  PlayButton(h),
                  IconButton(
                    tooltip: 'Next track',
                    onPressed: h.skipToNext,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class PlayButton extends StatelessWidget {
  const PlayButton(this.handler, {this.large = false, super.key});
  final SvaraHandler handler;
  final bool large;
  @override
  Widget build(BuildContext context) => StreamBuilder<PlaybackState>(
    stream: handler.playbackState,
    builder: (_, snapshot) {
      final playing = snapshot.data?.playing ?? false;
      final loading =
          snapshot.data?.processingState == AudioProcessingState.loading ||
          snapshot.data?.processingState == AudioProcessingState.buffering;
      return IconButton.filled(
        tooltip: playing ? 'Pause' : 'Play',
        iconSize: large ? 44 : 28,
        padding: EdgeInsets.all(large ? 20 : 8),
        onPressed: playing ? handler.pause : handler.play,
        icon: loading
            ? SizedBox(
                width: large ? 44 : 28,
                height: large ? 44 : 28,
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
      );
    },
  );
}

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  ColorScheme? accent;
  String? artId;
  String artworkKey(Track t) =>
      '${t.id}:${t.artwork}:${Theme.of(context).brightness.name}';
  Future<void> derive(Track t) async {
    final key = artworkKey(t);
    artId = key;
    accent = null;
    final bytes = await ArtworkCache.load(t, ref);
    if (bytes == null || !mounted) return;
    final scheme = await ColorScheme.fromImageProvider(
      provider: MemoryImage(bytes),
      brightness: Theme.of(context).brightness,
    );
    if (mounted && artId == key) setState(() => accent = scheme);
  }

  void openLyrics(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => const LyricsScreen()),
  );

  @override
  Widget build(BuildContext context) {
    final h = ref.watch(handlerProvider);
    return StreamBuilder<MediaItem?>(
      stream: h.mediaItem,
      builder: (_, snapshot) {
        final t = active(h);
        if (t != null && artId != artworkKey(t)) unawaited(derive(t));
        return Theme(
          data: Theme.of(context)
              .copyWith(colorScheme: accent ?? Theme.of(context).colorScheme),
          child: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  tooltip: 'Close player',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                title: const Text('Now playing'),
                actions: [
                  IconButton(
                    tooltip: 'Lyrics',
                    onPressed: t == null ? null : () => openLyrics(context),
                    icon: const Icon(Icons.lyrics_outlined),
                  ),
                  IconButton(
                    tooltip: 'Sleep timer',
                    onPressed: () async {
                      final minutes = await showModalBottomSheet<int>(
                        context: context,
                        showDragHandle: true,
                        builder: (_) => SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                title: Text(
                                  h.sleepUntil == null
                                      ? 'Sleep timer'
                                      : 'Stops at ${TimeOfDay.fromDateTime(h.sleepUntil!).format(context)}',
                                ),
                              ),
                              ...[0, 15, 30, 45, 60].map(
                                (m) => ListTile(
                                  title: Text(
                                    m == 0 ? 'Turn off' : '$m minutes',
                                  ),
                                  onTap: () => Navigator.pop(context, m),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                      if (minutes != null) {
                        h.sleepFor(
                          minutes == 0 ? null : Duration(minutes: minutes),
                        );
                        if (mounted) setState(() {});
                      }
                    },
                    icon: const Icon(Icons.bedtime_outlined),
                  ),
                  IconButton(
                    tooltip: 'Queue',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const QueueScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.queue_music),
                  ),
                ],
              ),
              body: t == null
                  ? const Center(child: Text('Choose a song to begin.'))
                  : SafeArea(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const SizedBox(height: 16),
                            StreamBuilder<Duration>(
                              stream: h.player.positionStream,
                              builder: (_, pos) {
                                final duration =
                                    h.player.duration ??
                                    Duration(milliseconds: t.durationMs);
                                final progress = duration.inMilliseconds <= 0
                                    ? 0.0
                                    : ((h.position).inMilliseconds /
                                              duration.inMilliseconds)
                                          .clamp(0.0, 1.0);
                                final size =
                                    (MediaQuery.sizeOf(context).width - 80)
                                        .clamp(160.0, 300.0);
                                return GestureDetector(
                                  onVerticalDragEnd: (details) {
                                    if ((details.primaryVelocity ?? 0) < -150) {
                                      openLyrics(context);
                                    }
                                  },
                                  child: Semantics(
                                    label:
                                        'Track progress ${(progress * 100).round()} percent. Swipe up for lyrics',
                                    child: SizedBox(
                                      width: size,
                                      height: size,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          SizedBox.expand(
                                            child: CircularProgressIndicator(
                                              value: progress,
                                              strokeWidth: 4,
                                              backgroundColor: Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                            ),
                                          ),
                                          ClipOval(
                                            child: TrackArt(t, size: size - 24),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 32),
                            Text(
                              t.title,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              t.artist,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (t.online)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'STREAMING FROM ${t.source.label.toUpperCase()}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ),
                            if (t.source == MediaSource.youtube)
                              TextButton.icon(
                                icon: const Icon(Icons.open_in_new, size: 18),
                                label: const Text('Open video in YouTube'),
                                onPressed: () async {
                                  try {
                                    await ref
                                        .read(libraryRepositoryProvider)
                                        .openUrl(t.sourceUrl);
                                  } catch (_) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'A browser or YouTube app is needed to open this video.',
                                              ),
                                            ),
                                          );
                                    }
                                  }
                                },
                              ),
                            IconButton(
                              tooltip:
                                  ref.watch(favoritesProvider).contains(t.id)
                                  ? 'Remove favorite'
                                  : 'Favorite',
                              onPressed: () => ref
                                  .read(favoritesProvider.notifier)
                                  .toggle(t.id),
                              icon: Icon(
                                ref.watch(favoritesProvider).contains(t.id)
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                              ),
                            ),
                            StreamBuilder<Duration?>(
                              stream: h.player.durationStream,
                              builder: (_, durationSnapshot) =>
                                  StreamBuilder<Duration>(
                                    stream: h.player.positionStream,
                                    builder: (_, pos) {
                                      final duration =
                                          durationSnapshot.data ??
                                          Duration(milliseconds: t.durationMs);
                                      final ms = duration.inMilliseconds
                                          .toDouble();
                                      final position = (h.position)
                                          .inMilliseconds
                                          .toDouble()
                                          .clamp(0.0, ms > 0 ? ms : 1.0);
                                      return Column(
                                        children: [
                                          Slider(
                                            semanticFormatterCallback: (v) =>
                                                timeLabel(
                                                  Duration(
                                                    milliseconds: v.round(),
                                                  ),
                                                ),
                                            value: position,
                                            max: ms > 0 ? ms : 1,
                                            onChanged: ms <= 0
                                                ? null
                                                : (value) => h.seek(
                                                    Duration(
                                                      milliseconds: value
                                                          .round(),
                                                    ),
                                                  ),
                                          ),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(timeLabel(h.position)),
                                              Text(timeLabel(duration)),
                                            ],
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                            ),
                            const SizedBox(height: 24),
                            StreamBuilder<PlaybackState>(
                              stream: h.playbackState,
                              builder: (_, state) => Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  IconButton(
                                    tooltip: 'Shuffle',
                                    isSelected: h.shuffleEnabled,
                                    onPressed: () => h.setShuffleMode(
                                      h.shuffleEnabled
                                          ? AudioServiceShuffleMode.none
                                          : AudioServiceShuffleMode.all,
                                    ),
                                    icon: const Icon(Icons.shuffle),
                                  ),
                                  IconButton(
                                    tooltip: 'Previous track',
                                    iconSize: 36,
                                    onPressed: h.skipToPrevious,
                                    icon: const Icon(
                                      Icons.skip_previous_rounded,
                                    ),
                                  ),
                                  PlayButton(h, large: true),
                                  IconButton(
                                    tooltip: 'Next track',
                                    iconSize: 36,
                                    onPressed: h.skipToNext,
                                    icon: const Icon(Icons.skip_next_rounded),
                                  ),
                                  IconButton(
                                    tooltip: 'Repeat: ${h.repeatMode.name}',
                                    isSelected:
                                        h.repeatMode !=
                                        AudioServiceRepeatMode.none,
                                    onPressed: () =>
                                        h.setRepeatMode(switch (h.repeatMode) {
                                          AudioServiceRepeatMode.none =>
                                            AudioServiceRepeatMode.all,
                                          AudioServiceRepeatMode.all =>
                                            AudioServiceRepeatMode.one,
                                          AudioServiceRepeatMode.one =>
                                            AudioServiceRepeatMode.none,
                                          _ => AudioServiceRepeatMode.none,
                                        }),
                                    icon: Icon(
                                      h.repeatMode == AudioServiceRepeatMode.one
                                          ? Icons.repeat_one
                                          : Icons.repeat,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (h.sleepUntil != null)
                              const Text('Sleep timer is on'),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ref.watch(handlerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Up next')),
      body: StreamBuilder<List<MediaItem>>(
        stream: h.queue,
        builder: (_, snapshot) => ReorderableListView.builder(
          itemCount: h.tracks.length,
          onReorderItem: (a, b) => h.reorder(a, b > a ? b + 1 : b),
          itemBuilder: (_, i) {
            final t = h.tracks[i];
            return ListTile(
              key: ValueKey('$i:${t.id}'),
              leading: TrackArt(t),
              title: Text(t.title),
              subtitle: Text(t.artist),
              onTap: () => h.skipToQueueItem(i),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Remove from queue',
                    onPressed: () => h.remove(i),
                    icon: const Icon(Icons.close),
                  ),
                  ReorderableDragStartListener(
                    index: i,
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
