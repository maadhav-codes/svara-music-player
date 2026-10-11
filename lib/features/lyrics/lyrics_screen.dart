import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/track.dart';
import '../player/svara_handler.dart';
import 'lyrics.dart';
import 'lyrics_repository.dart';

final lyricsRepositoryProvider = Provider<LyricsRepository>((ref) {
  final repository = LyricsRepository();
  ref.onDispose(repository.dispose);
  return repository;
});

class LyricsScreen extends ConsumerStatefulWidget {
  const LyricsScreen({super.key});
  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> {
  final scroll = ScrollController();
  final subscriptions = <StreamSubscription<dynamic>>[];
  late SvaraHandler handler;
  Track? track;
  Lyrics? lyrics;
  CancelToken? cancel;
  String? error;
  bool loading = false, follow = true, choosing = false;
  int active = -1, generation = 0;
  List<double> offsets = [];
  String? layoutKey;
  List<double> heights = [];

  @override
  void initState() {
    super.initState();
    handler = ref.read(handlerProvider);
    subscriptions.add(
      handler.mediaItem.listen((_) {
        final next = handler.current;
        if (next?.id != track?.id ||
            next?.title != track?.title ||
            next?.artist != track?.artist ||
            next?.album != track?.album ||
            next?.durationMs != track?.durationMs ||
            next?.modified != track?.modified) {
          load();
        }
      }),
    );
    subscriptions.add(handler.player.positionStream.listen((_) => tick()));
    subscriptions.add(handler.playbackState.listen((_) => tick()));
    load();
  }

  Future<void> load({bool refresh = false}) async {
    cancel?.cancel();
    cancel = CancelToken();
    final token = cancel!;
    final request = ++generation;
    track = handler.current;
    final current = track;
    setState(() {
      lyrics = null;
      error = null;
      loading = current != null;
      active = -1;
      follow = true;
      layoutKey = null;
      offsets = [];
    });
    if (current == null) return;
    try {
      final result = await ref
          .read(lyricsRepositoryProvider)
          .load(current, cancelToken: token, refresh: refresh);
      if (!mounted || request != generation) return;
      setState(() {
        lyrics = result;
        loading = false;
        active = result?.activeIndex(handler.position) ?? -1;
      });
      scheduleFollow();
    } catch (e) {
      if (!mounted || request != generation || token.isCancelled) return;
      setState(() {
        loading = false;
        error = e is LyricsException
            ? e.message
            : 'Lyrics could not be loaded. Please retry.';
      });
    }
  }

  void tick() {
    if (!mounted || lyrics == null) return;
    final next = lyrics!.activeIndex(handler.position);
    if (next == active) return;
    setState(() => active = next);
    scheduleFollow();
  }

  void scheduleFollow() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted ||
        !follow ||
        active < 0 ||
        active >= offsets.length ||
        !scroll.hasClients) {
      return;
    }
    final target = (offsets[active] - scroll.position.viewportDimension * .35)
        .clamp(0.0, scroll.position.maxScrollExtent);
    final media = MediaQuery.of(context);
    if (media.disableAnimations || media.accessibleNavigation) {
      scroll.jumpTo(target);
    } else {
      unawaited(
        scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        ),
      );
    }
  });
  Future<void> folder() async {
    final current = track;
    if (current == null || choosing) return;
    setState(() => choosing = true);
    try {
      final picked = await ref
          .read(lyricsRepositoryProvider)
          .chooseFolder(current);
      if (mounted && picked && track?.id == current.id) {
        await load(refresh: true);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Folder access failed. Please choose the folder again.',
        );
      }
    } finally {
      if (mounted) setState(() => choosing = false);
    }
  }

  @override
  void dispose() {
    cancel?.cancel();
    for (final s in subscriptions) {
      unawaited(s.cancel());
    }
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = track;
    final data = lyrics;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lyrics'),
        actions: [
          IconButton(
            tooltip: 'Retry lyrics',
            onPressed: loading ? null : () => load(refresh: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (current != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                child: Text(
                  '${current.title}\n${current.artist}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            if (data != null)
              Text(
                data.source == 'LRCLIB'
                    ? 'Lyrics from LRCLIB'
                    : 'Local .lrc lyrics',
              ),
            if (current != null && !current.online)
              TextButton.icon(
                onPressed: choosing ? null : folder,
                icon: const Icon(Icons.folder_open),
                label: const Text('Choose song folder for .lrc'),
              ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : data == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          error ??
                              (current == null
                                  ? 'Choose a song to begin.'
                                  : 'No lyrics found for this recording. Check the song’s title and artist, or add a matching local .lrc file.'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : data.instrumental
                  ? const Center(child: Text('Instrumental · no lyrics'))
                  : data.lines.isEmpty
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const Text('Timing unavailable'),
                          const SizedBox(height: 16),
                          SelectableText(
                            data.plain,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final style = Theme.of(context).textTheme.titleLarge!
                            .copyWith(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                            );
                        final scale = MediaQuery.textScalerOf(context);
                        final key =
                            '${constraints.maxWidth}:${scale.scale(24)}:${data.hashCode}';
                        if (key != layoutKey) {
                          layoutKey = key;
                          var offset = 0.0;
                          offsets = [];
                          heights = [];
                          for (final line in data.lines) {
                            final painter = TextPainter(
                              text: TextSpan(
                                text: line.text.isEmpty ? '♪' : line.text,
                                style: style,
                              ),
                              textDirection: Directionality.of(context),
                              textScaler: scale,
                            )..layout(maxWidth: constraints.maxWidth - 48);
                            final height = (painter.height + 32).clamp(
                              64.0,
                              double.infinity,
                            );
                            painter.dispose();
                            offsets.add(offset);
                            heights.add(height);
                            offset += height;
                          }
                          scheduleFollow();
                        }
                        return NotificationListener<UserScrollNotification>(
                          onNotification: (n) {
                            if (n.direction != ScrollDirection.idle && follow) {
                              setState(() => follow = false);
                            }
                            return false;
                          },
                          child: ListView.builder(
                            controller: scroll,
                            itemCount: data.lines.length,
                            itemExtentBuilder: (index, _) => heights[index],
                            itemBuilder: (context, index) {
                              final line = data.lines[index];
                              final selected = index == active;
                              return Semantics(
                                selected: selected,
                                label: 'Seek to ${line.time.inSeconds} seconds',
                                child: InkWell(
                                  onTap: () {
                                    unawaited(handler.seek(line.time));
                                    setState(() => follow = true);
                                    scheduleFollow();
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 16,
                                    ),
                                    child: Text(
                                      line.text.isEmpty ? '♪' : line.text,
                                      style: style.copyWith(
                                        color: selected
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
            if (data != null && data.lines.isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  setState(() => follow = true);
                  scheduleFollow();
                },
                icon: Icon(
                  follow ? Icons.my_location : Icons.location_searching,
                ),
                label: Text(follow ? 'Following playback' : 'Follow playback'),
              ),
          ],
        ),
      ),
    );
  }
}
