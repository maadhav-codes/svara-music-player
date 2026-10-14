import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/track.dart';
import '../../core/track_presentation.dart';
import '../../core/widgets/track_version_labels.dart';
import '../../core/artwork.dart';
import '../../core/widgets/music_empty_state.dart';
import '../playlists/playlists_screen.dart';
import '../discovery/personalized_feed.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({this.onDiscover, super.key});
  final VoidCallback? onDiscover;
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with WidgetsBindingObserver {
  final List<Track> tracks = [];
  final searchController = TextEditingController();
  String query = '', filter = 'All', sort = 'Title';
  String? group, error;
  bool allowed = false, loading = true, permanentlyDenied = false;
  Future<void>? _refreshTask;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  Future<void> refresh({bool request = false}) =>
      _refreshTask ??= _refresh(request: request)
          .whenComplete(() => _refreshTask = null);

  Future<void> _refresh({required bool request}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final repo = ref.read(libraryRepositoryProvider);
      final permission = await repo.permission(request: request);
      if (!mounted) return;
      setState(() => allowed = permission);
      if (!allowed) {
        final blocked = await repo.isPermissionPermanentlyDenied();
        if (!mounted) return;
        setState(() {
          permanentlyDenied = blocked;
          tracks.clear();
        });
        return;
      }
      final saved = await repo.all();
      if (!mounted) return;
      setState(() {
        tracks
          ..clear()
          ..addAll(saved);
      });
      await repo.refresh();
      final current = await repo.all();
      if (!mounted) return;
      setState(() {
        tracks
          ..clear()
          ..addAll(current);
      });
    } catch (_) {
      if (mounted) error = 'Could not refresh phone music. Please retry.';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(favoritesProvider);
    if (!allowed || tracks.isEmpty) {
      return RefreshIndicator(
        onRefresh: refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: loading
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Finding your music…'),
                        ],
                      )
                    : MusicEmptyState(
                        title: error != null
                            ? 'Couldn’t load your music'
                            : 'Your library is empty',
                        message: error != null
                            ? 'Please try again to find music on your phone.'
                            : !allowed
                            ? permanentlyDenied
                                  ? 'Enable music access in app settings to find songs on your phone.'
                                  : 'Allow music access to bring the songs on your phone into Svara.'
                            : 'Add music to your phone, then refresh your library. You can also explore music in Discover.',
                        actionLabel: error != null
                            ? 'Retry'
                            : !allowed
                            ? permanentlyDenied
                                  ? 'Open app settings'
                                  : 'Allow music access'
                            : widget.onDiscover != null
                            ? 'Explore Discover'
                            : 'Refresh music',
                        onAction: () async {
                          if (error != null) {
                            await refresh();
                          } else if (!allowed) {
                            if (permanentlyDenied) {
                              try {
                                await ref
                                    .read(libraryRepositoryProvider)
                                    .openSettings();
                              } catch (_) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Could not open app settings. Please try again.',
                                    ),
                                  ),
                                );
                              }
                            } else {
                              await refresh(request: true);
                            }
                          } else if (widget.onDiscover != null) {
                            widget.onDiscover!();
                          } else {
                            await refresh();
                          }
                        },
                        icon: Icons.library_music_outlined,
                      ),
              ),
            ),
          ],
        ),
      );
    }
    final list = tracks
        .where(
          (t) =>
              '${t.title} ${t.artist} ${t.album} ${t.folder}'
                  .toLowerCase()
                  .contains(query.toLowerCase()) &&
              (group == null ||
                  (filter == 'Albums'
                          ? t.album
                          : filter == 'Artists'
                          ? t.artist
                          : t.folder) ==
                      group),
        )
        .toList();
    list.sort(
      (a, b) => switch (sort) {
        'Artist' => a.artist.compareTo(b.artist),
        'Duration' => a.durationMs.compareTo(b.durationMs),
        'Recent' => b.modified.compareTo(a.modified),
        _ => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      },
    );
    final grouping =
        {'Albums', 'Artists', 'Folders'}.contains(filter) && group == null;
    final groups = grouping
        ? list
              .map(
                (t) => filter == 'Albums'
                    ? t.album
                    : filter == 'Artists'
                    ? t.artist
                    : t.folder,
              )
              .toSet()
              .toList()
        : <String>[];
    groups.sort();
    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          onRefresh: refresh,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: searchController,
                        decoration: const InputDecoration(
                          hintText: 'Find a song, artist, album…',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) {
                          setState(() => query = value);
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              group ??
                                  '${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'}',
                            ),
                          ),
                          if (group != null)
                            TextButton(
                              onPressed: () => setState(() => group = null),
                              child: const Text('All groups'),
                            ),
                          IconButton(
                            tooltip: 'Mix my library',
                            icon: const Icon(Icons.shuffle_rounded),
                            onPressed: () async {
                              final history = await ref
                                  .read(storeProvider)
                                  .history();
                              if (!mounted) return;
                              await ref
                                  .read(handlerProvider)
                                  .setQueue(
                                    quickMix(tracks, favorites, history),
                                  );
                            },
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Sort songs',
                            onSelected: (value) => setState(() => sort = value),
                            itemBuilder: (_) =>
                                ['Title', 'Artist', 'Duration', 'Recent']
                                    .map(
                                      (s) => PopupMenuItem(
                                        value: s,
                                        child: Text(s),
                                      ),
                                    )
                                    .toList(),
                            icon: const Icon(Icons.sort),
                          ),
                        ],
                      ),
                      if (loading) const LinearProgressIndicator(),
                      if (error != null)
                        TextButton(
                          onPressed: refresh,
                          child: Text('$error Retry'),
                        ),
                    ],
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _FilterHeader(
                  height: _filterHeight(context, constraints.maxWidth),
                  child: Material(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: _filters
                            .map(
                              (name) => ChoiceChip(
                                label: Text(name),
                                showCheckmark: false,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                labelPadding: EdgeInsets.zero,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.padded,
                                selected: filter == name,
                                onSelected: (_) {
                                  setState(() {
                                    filter = name;
                                    group = null;
                                  });
                                },
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ),
              ),
              if (query.trim().isEmpty && filter == 'All' && group == null)
                const SliverToBoxAdapter(child: PersonalizedFeed()),
              if (allowed &&
                  !loading &&
                  list.isEmpty &&
                  filter != 'Recently played')
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: MusicEmptyState(
                      title: query.isNotEmpty
                          ? 'No songs found'
                          : 'No songs in this group',
                      message: query.isNotEmpty
                          ? 'Try another search or search online music in Discover.'
                          : 'Choose another group or explore music in Discover.',
                      actionLabel: widget.onDiscover != null
                          ? 'Explore Discover'
                          : 'Refresh music',
                      onAction: widget.onDiscover ?? () => refresh(),
                      icon: query.isNotEmpty
                          ? Icons.search_rounded
                          : Icons.library_music_outlined,
                    ),
                  ),
                ),
              if (filter == 'Recently played')
                SliverToBoxAdapter(
                  child: FutureBuilder<Map<String, int>>(
                    future: ref.read(storeProvider).history(),
                    builder: (context, snapshot) {
                      final recent =
                          list
                              .where(
                                (t) =>
                                    snapshot.data?.containsKey(t.id) ?? false,
                              )
                              .toList()
                            ..sort(
                              (a, b) => snapshot.data![b.id]!.compareTo(
                                snapshot.data![a.id]!,
                              ),
                            );
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (recent.isEmpty) {
                        return MusicEmptyState(
                          title: 'Your listening story starts here',
                          message:
                              'Play a song or explore a new sound in Discover.',
                          actionLabel: widget.onDiscover != null
                              ? 'Explore Discover'
                              : 'Show all songs',
                          onAction:
                              widget.onDiscover ??
                              () => setState(() => filter = 'All'),
                        );
                      }
                      return Column(
                        children: recent
                            .map(
                              (t) => SongTile(
                                t,
                                onPlay: () => ref
                                    .read(handlerProvider)
                                    .setQueue(recent, index: recent.indexOf(t)),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                )
              else if (grouping)
                SliverList.builder(
                  itemCount: groups.length,
                  itemBuilder: (_, i) => ListTile(
                    leading: Icon(
                      filter == 'Folders'
                          ? Icons.folder_outlined
                          : Icons.album_outlined,
                    ),
                    title: Text(groups[i].isEmpty ? 'Unknown' : groups[i]),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() => group = groups[i]),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) => SongTile(
                    list[i],
                    onPlay: () =>
                        ref.read(handlerProvider).setQueue(list, index: i),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      },
    );
  }
}

const _filters = ['All', 'Artists', 'Albums', 'Folders', 'Recently played'];

// Match the chip padding and wrap spacing so the pinned header can grow with text.
double _filterHeight(BuildContext context, double width) {
  final style =
      Theme.of(context).chipTheme.labelStyle ??
      Theme.of(context).textTheme.labelLarge!;
  var rows = 1;
  var usedWidth = 0.0;
  var rowHeight = 48.0;
  for (final label in _filters) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final chipWidth = painter.width + 26;
    final chipHeight = painter.height + 18;
    if (chipHeight > rowHeight) rowHeight = chipHeight;
    if (usedWidth > 0 && usedWidth + 8 + chipWidth > width - 32) {
      rows++;
      usedWidth = chipWidth;
    } else {
      usedWidth += (usedWidth == 0 ? 0 : 8) + chipWidth;
    }
    painter.dispose();
  }
  return 24 + rows * rowHeight + (rows - 1) * 4;
}

class _FilterHeader extends SliverPersistentHeaderDelegate {
  _FilterHeader({required this.child, required this.height});
  final Widget child;
  final double height;
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => SizedBox.expand(child: child);
  @override
  bool shouldRebuild(covariant _FilterHeader oldDelegate) => true;
}

class SongTile extends ConsumerWidget {
  const SongTile(
    this.track, {
    required this.onPlay,
    this.onRemove,
    this.removeLabel,
    super.key,
  });
  final Track track;
  final VoidCallback onPlay;
  final VoidCallback? onRemove;
  final String? removeLabel;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display = track.presentation;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      horizontalTitleGap: 12,
      minLeadingWidth: 44,
      leading: TrackArt(track, size: 44),
      title: Semantics(
        label: track.title,
        excludeSemantics: true,
        child: Text(
          display.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${track.recordingArtist}${track.online ? ' • ${track.source.label}' : ''}${track.streamable ? '' : ' • Unavailable'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (display.versions.isNotEmpty || display.labels.isNotEmpty) ...[
            const SizedBox(height: 4),
            TrackVersionLabels(display),
          ],
        ],
      ),
      onLongPress: () => showOriginalTrackTitle(context, track),
      onTap: track.streamable
          ? onPlay
          : () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'This track is unavailable on ${track.source.label}.',
                ),
              ),
            ),
      trailing: IconButton(
        tooltip: 'Song options',
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: const Icon(Icons.more_vert),
        onPressed: () => showTrackOptions(
          context,
          ref,
          track,
          onRemove: onRemove,
          removeLabel: removeLabel,
        ),
      ),
    );
  }
}

Future<void> showTrackOptions(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  VoidCallback? onRemove,
  String? removeLabel,
}) async {
  final favorite = ref.read(favoritesProvider).contains(track.id);
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: TrackArt(track, size: 44),
              title: Text(track.title),
              subtitle: Text(track.artist),
            ),
            const Divider(),
            for (final option in [
              ('playlist', Icons.playlist_add, 'Add to Playlist'),
              ('next', Icons.skip_next, 'Play Next'),
              ('queue', Icons.queue_music, 'Add to Queue'),
              (
                'favorite',
                favorite ? Icons.favorite : Icons.favorite_border,
                favorite ? 'Unfavorite' : 'Favorite',
              ),
              (
                'info',
                Icons.info_outline,
                track.online ? 'Track Info' : 'Track Info / File Details',
              ),
              if (onRemove != null)
                (
                  'remove',
                  Icons.remove_circle_outline,
                  removeLabel ?? 'Remove',
                ),
            ])
              ListTile(
                leading: Icon(option.$2),
                title: Text(option.$3),
                enabled:
                    track.streamable || !{'next', 'queue'}.contains(option.$1),
                onTap: () => Navigator.pop(context, option.$1),
              ),
          ],
        ),
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'favorite':
      await ref.read(favoritesProvider.notifier).toggle(track);
    case 'playlist':
      await addToPlaylist(context, ref, track);
    case 'next':
    case 'queue':
      final h = ref.read(handlerProvider);
      final queue = [...h.tracks];
      final index = h.activeIndex;
      final at = h.position;
      final playing = h.player.playing;
      queue.insert(
        action == 'next' && queue.isNotEmpty
            ? (index + 1).clamp(0, queue.length)
            : queue.length,
        track,
      );
      await h.setQueue(queue, index: index, position: at, start: playing);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(action == 'next' ? 'Playing next' : 'Added to queue'),
          ),
        );
      }
    case 'remove':
      onRemove?.call();
    case 'info':
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Track Info',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                for (final detail in [
                  ('Title', track.title),
                  (track.online ? 'YouTube uploader' : 'Artist', track.artist),
                  if (track.catalog != null) ...[
                    (
                      'Recording artist',
                      (track.catalog!['artists'] as List).isEmpty
                          ? 'Unknown'
                          : (track.catalog!['artists'] as List).join(', '),
                    ),
                    ('Catalog source', track.catalog!['sourceName'] as String),
                    ('Catalog URL', track.catalog!['sourceUrl'] as String),
                    if (track.catalog!['metadataUrl'] != null)
                      (
                        'MusicBrainz recording',
                        track.catalog!['metadataUrl'] as String,
                      ),
                  ],
                  ('Album', track.album.isEmpty ? 'Unknown' : track.album),
                  (
                    'Duration',
                    track.durationMs > 0
                        ? '${track.durationMs ~/ 60000}:${((track.durationMs ~/ 1000) % 60).toString().padLeft(2, '0')}'
                        : 'Unknown',
                  ),
                  ('Source', track.source.label),
                  (
                    'Availability',
                    track.streamable ? 'Available' : 'Unavailable',
                  ),
                  if (!track.online && track.folder.isNotEmpty)
                    ('Folder', track.folder),
                  (
                    track.online ? 'Source URL' : 'File location',
                    track.sourceUrl,
                  ),
                ]) ...[
                  Text(
                    detail.$1,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  SelectableText(detail.$2),
                  const SizedBox(height: 12),
                ],
                if (track.online)
                  TextButton.icon(
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open in YouTube'),
                    onPressed: () async {
                      try {
                        await ref
                            .read(libraryRepositoryProvider)
                            .openUrl(track.sourceUrl);
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'A browser or YouTube app is needed to open this song.',
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
      );
  }
}
