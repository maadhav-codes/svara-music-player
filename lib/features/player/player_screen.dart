import '../../core/app_routes.dart';
import '../lyrics/lyrics_screen.dart';

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/track.dart';
import '../../core/artwork.dart';
import '../library/library_screen.dart';
import '../playlists/playlists_screen.dart';
import 'svara_handler.dart';

String timeLabel(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
Track? active(SvaraHandler h) => h.current;

class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});
  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  Offset _drag = Offset.zero;
  Offset _dragStart = Offset.zero;
  bool _expanded = false;
  final _slide = ValueNotifier<double>(0);
  void _setDrag(Offset drag) {
    _drag = drag;
    _slide.value = (drag.dx * .2).clamp(-40.0, 40.0);
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  Future<void> _expand() async {
    if (_expanded) return;
    _expanded = true;
    try {
      await Navigator.push<void>(
        context,
        AppPageRoute(builder: (_) => const PlayerScreen()),
      );
    } finally {
      _expanded = false;
    }
  }

  void _finishSwipe(DragEndDetails details, SvaraHandler handler) {
    final horizontal = _drag.dx.abs() > _drag.dy.abs();
    final distance = horizontal ? _drag.dx : _drag.dy;
    final speed = horizontal
        ? details.velocity.pixelsPerSecond.dx
        : details.velocity.pixelsPerSecond.dy;
    _setDrag(Offset.zero);
    // Require deliberate travel even for a fast flick, so small finger movement
    // on the play and next buttons cannot accidentally skip a recording.
    if (distance.abs() < 48 && !(distance.abs() >= 20 && speed.abs() >= 500)) {
      return;
    }
    if (horizontal) {
      final before = handler.activeIndex;
      // The shared handler selects the logical queue item before loading audio.
      final change = distance < 0
          ? handler.skipToNext()
          : handler.skipToPrevious();
      if (handler.activeIndex != before) {
        unawaited(HapticFeedback.selectionClick());
      }
      unawaited(change);
    } else if (distance < 0) {
      unawaited(_expand());
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = ref.watch(handlerProvider);
    return StreamBuilder<MediaItem?>(
      stream: h.mediaItem,
      builder: (_, snapshot) {
        final t = active(h);
        if (t == null) return const SizedBox();
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          elevation: 2,
          shadowColor: Theme.of(context).colorScheme.shadow
              .withValues(alpha: .16),
          child: Stack(
            children: [
              GestureDetector(
                excludeFromSemantics: true,
                behavior: HitTestBehavior.opaque,
                onPanDown: (details) {
                  _dragStart = details.localPosition;
                  _setDrag(Offset.zero);
                },
                onPanStart: (details) =>
                    _setDrag(details.localPosition - _dragStart),
                onPanUpdate: (details) =>
                    _setDrag(details.localPosition - _dragStart),
                onPanCancel: () => _setDrag(Offset.zero),
                onPanEnd: (details) => _finishSwipe(details, h),
                child: Listener(
                  onPointerCancel: (_) => _setDrag(Offset.zero),
                  child: InkWell(
                    onTap: _expand,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: ClipRect(
                              child: ValueListenableBuilder<double>(
                                valueListenable: _slide,
                                child: Row(
                                  children: [
                                    TrackArt(t, size: 48),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            t.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            t.recordingArtist,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                builder: (context, value, child) {
                                  final media = MediaQuery.of(context);
                                  final reduced =
                                      media.disableAnimations ||
                                      media.accessibleNavigation;
                                  return TweenAnimationBuilder<double>(
                                    tween: Tween(end: reduced ? 0 : value),
                                    duration: reduced || _drag != Offset.zero
                                        ? Duration.zero
                                        : const Duration(milliseconds: 160),
                                    curve: Curves.easeOut,
                                    builder: (_, x, child) =>
                                        Transform.translate(
                                          offset: Offset(x, 0),
                                          child: child,
                                        ),
                                    child: child,
                                  );
                                },
                              ),
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
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ExcludeSemantics(
                  child: StreamBuilder<Duration?>(
                    key: ValueKey(t.id),
                    stream: h.player.durationStream,
                    builder: (_, durationSnapshot) => StreamBuilder<Duration>(
                      stream: h.player.positionStream,
                      builder: (_, positionSnapshot) {
                        final reportedDuration = durationSnapshot.data;
                        final duration =
                            reportedDuration != null &&
                                reportedDuration > Duration.zero
                            ? reportedDuration
                            : Duration(milliseconds: t.durationMs);
                        final position = h.position;
                        final total = duration.inMilliseconds;
                        return LinearProgressIndicator(
                          value: total > 0
                              ? (position.inMilliseconds / total).clamp(
                                  0.0,
                                  1.0,
                                )
                              : 0,
                          minHeight: 2,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: .3),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
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
    initialData: handler.playbackState.value,
    builder: (_, snapshot) {
      final playing = snapshot.data?.playing ?? false;
      final loading =
          snapshot.data?.processingState == AudioProcessingState.loading ||
          snapshot.data?.processingState == AudioProcessingState.buffering;
      return IconButton.filled(
        tooltip: playing ? 'Pause' : 'Play',
        iconSize: large ? 32 : 28,
        padding: EdgeInsets.all(large ? 14 : 8),
        onPressed: playing ? handler.pause : handler.play,
        icon: loading
            ? SizedBox(
                width: large ? 32 : 28,
                height: large ? 32 : 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.onPrimary,
                  backgroundColor: Theme.of(context).colorScheme.onPrimary
                      .withValues(alpha: 0.2),
                  semanticsLabel: 'Loading track',
                ),
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
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void openLyrics(BuildContext context) => Navigator.push(
    context,
    AppPageRoute<void>(builder: (_) => const LyricsScreen()),
  );

  @override
  Widget build(BuildContext context) {
    final h = ref.watch(handlerProvider);
    return StreamBuilder<MediaItem?>(
      stream: h.mediaItem,
      builder: (_, snapshot) {
        final t = active(h);
        return Theme(
          data: Theme.of(context),
          child: Builder(
            builder: (context) => _PlayerDismissGesture(
              scroll: _scroll,
              child: Scaffold(
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
                        AppPageRoute<void>(builder: (_) => const QueueScreen()),
                      ),
                      icon: const Icon(Icons.queue_music),
                    ),
                  ],
                ),
                body: t == null
                    ? const Center(child: Text('Choose a song to begin.'))
                    : SafeArea(
                        child: LayoutBuilder(
                          builder: (context, viewport) {
                            final landscape =
                                viewport.maxWidth >= 600 &&
                                viewport.maxWidth > viewport.maxHeight;
                            final horizontalPadding = viewport.maxWidth < 360
                                ? 12.0
                                : 24.0;
                            Widget artwork(double size) => GestureDetector(
                              key: const ValueKey('player-artwork'),
                              onVerticalDragEnd: (details) {
                                if ((details.primaryVelocity ?? 0) < -150) {
                                  openLyrics(context);
                                }
                              },
                              child: Semantics(
                                label: 'Album artwork. Swipe up for lyrics',
                                child: TrackArt(t, size: size),
                              ),
                            );
                            Widget metadata() => Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  t.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  t.recordingArtist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      tooltip:
                                          ref
                                              .watch(favoritesProvider)
                                              .contains(t.id)
                                          ? 'Remove favorite'
                                          : 'Favorite',
                                      onPressed: () async {
                                        String message;
                                        try {
                                          await ref
                                              .read(favoritesProvider.notifier)
                                              .toggle(t);
                                          if (!context.mounted) return;
                                          message =
                                              ref
                                                  .read(favoritesProvider)
                                                  .contains(t.id)
                                              ? 'Added to Favorites in Playlists'
                                              : 'Removed from Favorites';
                                        } catch (_) {
                                          message = 'Could not update Favorites. Please try again.';
                                        }
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context)
                                          ..hideCurrentSnackBar()
                                          ..showSnackBar(
                                            SnackBar(
                                              content: Text(message),
                                              duration: const Duration(
                                                seconds: 2,
                                              ),
                                            ),
                                          );
                                      },
                                      icon: Icon(
                                        ref
                                                .watch(favoritesProvider)
                                                .contains(t.id)
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                      ),
                                      color:
                                          ref
                                              .watch(favoritesProvider)
                                              .contains(t.id)
                                          ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                          : null,
                                    ),
                                    IconButton(
                                      tooltip: 'Add to playlist',
                                      onPressed: () =>
                                          addToPlaylist(context, ref, t),
                                      icon: const Icon(Icons.playlist_add),
                                    ),
                                    IconButton(
                                      tooltip: 'Song options',
                                      onPressed: () =>
                                          showTrackOptions(context, ref, t),
                                      icon: const Icon(Icons.more_vert),
                                    ),
                                  ],
                                ),
                              ],
                            );
                            Widget controls() => Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                StreamBuilder<Duration?>(
                                  stream: h.player.durationStream,
                                  builder: (_, durationSnapshot) =>
                                      StreamBuilder<Duration>(
                                        stream: h.player.positionStream,
                                        builder: (_, pos) {
                                          final duration =
                                              durationSnapshot.data ??
                                              Duration(
                                                milliseconds: t.durationMs,
                                              );
                                          final ms = duration.inMilliseconds
                                              .toDouble();
                                          final position = (h.position)
                                              .inMilliseconds
                                              .toDouble()
                                              .clamp(0.0, ms > 0 ? ms : 1.0);
                                          return Column(
                                            children: [
                                              Slider(
                                                semanticFormatterCallback:
                                                    (v) => timeLabel(
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
                                                    MainAxisAlignment
                                                        .spaceBetween,
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
                                const SizedBox(height: 12),
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
                                      PlayButton(
                                        h,
                                        large:
                                            !landscape ||
                                            viewport.maxWidth >= 640,
                                      ),
                                      IconButton(
                                        tooltip: 'Next track',
                                        iconSize: 36,
                                        onPressed: h.skipToNext,
                                        icon: const Icon(
                                          Icons.skip_next_rounded,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Repeat: ${h.repeatMode.name}',
                                        isSelected:
                                            h.repeatMode !=
                                            AudioServiceRepeatMode.none,
                                        onPressed: () => h.setRepeatMode(
                                          switch (h.repeatMode) {
                                            AudioServiceRepeatMode.none =>
                                              AudioServiceRepeatMode.all,
                                            AudioServiceRepeatMode.all =>
                                              AudioServiceRepeatMode.one,
                                            AudioServiceRepeatMode.one =>
                                              AudioServiceRepeatMode.none,
                                            _ => AudioServiceRepeatMode.none,
                                          },
                                        ),
                                        icon: Icon(
                                          h.repeatMode ==
                                                  AudioServiceRepeatMode.one
                                              ? Icons.repeat_one
                                              : Icons.repeat,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (h.sleepUntil != null)
                                  const Text('Sleep timer is on'),
                              ],
                            );
                            Widget responsiveArtwork() => Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 300,
                                  maxHeight: 300,
                                ),
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: FittedBox(child: artwork(300)),
                                ),
                              ),
                            );

                            Widget details({
                              required bool includeArtwork,
                            }) => Column(
                              children: [
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (includeArtwork)
                                        Flexible(
                                          flex: viewport.maxHeight >= 600
                                              ? 3
                                              : 1,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 16,
                                            ),
                                            child: responsiveArtwork(),
                                          ),
                                        ),
                                      Flexible(
                                        flex: viewport.maxHeight >= 600 ? 3 : 6,
                                        child: SingleChildScrollView(
                                          controller: _scroll,
                                          child: metadata(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                controls(),
                              ],
                            );
                            return Padding(
                              padding: EdgeInsets.fromLTRB(
                                horizontalPadding,
                                8,
                                horizontalPadding,
                                12,
                              ),
                              child: landscape
                                  ? Row(
                                      children: [
                                        Expanded(child: responsiveArtwork()),
                                        const SizedBox(width: 24),
                                        Expanded(
                                          child: details(includeArtwork: false),
                                        ),
                                      ],
                                    )
                                  : details(includeArtwork: true),
                            );
                          },
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

// Observe pointer movement without competing with the scroll view, lyrics
// gesture or seek slider. Only a downward gesture starting at the top dismisses.
class _PlayerDismissGesture extends StatefulWidget {
  const _PlayerDismissGesture({required this.scroll, required this.child});
  final ScrollController scroll;
  final Widget child;
  @override
  State<_PlayerDismissGesture> createState() => _PlayerDismissGestureState();
}

class _PlayerDismissGestureState extends State<_PlayerDismissGesture> {
  final pointers = <int>{};
  int? pointer;
  Offset origin = Offset.zero;
  VelocityTracker? velocity;
  bool eligible = false;
  void down(PointerDownEvent event) {
    pointers.add(event.pointer);
    if (pointers.length != 1) {
      pointer = null;
      return;
    }
    pointer = event.pointer;
    origin = event.position;
    eligible =
        !widget.scroll.hasClients ||
        widget.scroll.position.pixels <=
            widget.scroll.position.minScrollExtent + 1;
    velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void up(PointerUpEvent event) {
    pointers.remove(event.pointer);
    if (pointer != event.pointer) return;
    pointer = null;
    final delta = event.position - origin;
    final speed = velocity?.getVelocity().pixelsPerSecond.dy ?? 0;
    if (eligible &&
        delta.dy > delta.dx.abs() * 1.5 &&
        (delta.dy >= 100 || (delta.dy >= 48 && speed >= 500)) &&
        ModalRoute.of(context)?.isCurrent == true) {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: down,
    onPointerMove: (event) {
      if (event.pointer == pointer) {
        velocity?.addPosition(event.timeStamp, event.position);
      }
    },
    onPointerUp: up,
    onPointerCancel: (event) {
      pointers.remove(event.pointer);
      pointer = null;
    },
    child: widget.child,
  );
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
            return Row(
              key: ValueKey('$i:${t.id}'),
              children: [
                Expanded(
                  child: SongTile(
                    t,
                    onPlay: () => h.skipToQueueItem(i),
                    onRemove: () => h.remove(i),
                    removeLabel: 'Remove from queue',
                  ),
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
            );
          },
        ),
      ),
    );
  }
}
