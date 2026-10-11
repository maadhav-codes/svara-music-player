import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/track.dart';
import '../../core/artwork.dart';
import '../playlists/playlists_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with WidgetsBindingObserver {
  final List<Track> tracks = [];
  String query = '', filter = 'Songs', sort = 'Title';
  String? group, error;
  bool allowed = false, loading = true, more = true, paging = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  Future<void> refresh({bool request = false}) async {
    if (paging) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final repo = ref.read(libraryRepositoryProvider);
      allowed = await repo.permission(request: request);
      if (!allowed) {
        tracks.clear();
        return;
      }
      // Show persisted local data before querying MediaStore.
      final cached = await repo.page(0);
      if (mounted) {
        setState(() {
          tracks
            ..clear()
            ..addAll(cached);
          loading = false;
        });
      }
      await repo.refresh();
      final first = await repo.page(0);
      tracks
        ..clear()
        ..addAll(first);
      more = first.length == 200;
    } catch (e) {
      error = 'Could not refresh phone music. Please retry.';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> loadMore() async {
    if (!more || paging || !allowed) return;
    paging = true;
    try {
      final page = await ref
          .read(libraryRepositoryProvider)
          .page(tracks.length);
      tracks.addAll(page);
      more = page.length == 200;
    } catch (_) {
      error = 'Could not load more phone music. Pull to refresh.';
      more = false;
    } finally {
      paging = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> loadAll() async {
    while (more && mounted && allowed && !paging) {
      await loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(favoritesProvider);
    final list = tracks
        .where(
          (t) =>
              '${t.title} ${t.artist} ${t.album} ${t.folder}'
                  .toLowerCase()
                  .contains(query.toLowerCase()) &&
              (filter != 'Favorites' || favorites.contains(t.id)) &&
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
    return RefreshIndicator(
      onRefresh: refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 500) unawaited(loadMore());
          return false;
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your music.\nYour moment.',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'ON YOUR PHONE',
                      style: TextStyle(
                        letterSpacing: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Find a song, artist, album…',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        setState(() => query = value);
                        unawaited(loadAll());
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: tracks.isEmpty
                          ? null
                          : () async {
                              await loadAll();
                              final history = await ref
                                  .read(storeProvider)
                                  .history();
                              await ref
                                  .read(handlerProvider)
                                  .setQueue(
                                    quickMix(tracks, favorites, history),
                                  );
                            },
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Quick Mix'),
                    ),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children:
                            [
                                  'Songs',
                                  'Albums',
                                  'Artists',
                                  'Folders',
                                  'Favorites',
                                  'Recently played',
                                ]
                                .map(
                                  (name) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text(name),
                                      selected: filter == name,
                                      onSelected: (_) async {
                                        setState(() {
                                          filter = name;
                                          group = null;
                                        });
                                        await loadAll();
                                      },
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            group ??
                                '${tracks.length}${more ? '+' : ''} tracks',
                          ),
                        ),
                        if (group != null)
                          TextButton(
                            onPressed: () => setState(() => group = null),
                            child: const Text('All groups'),
                          ),
                        PopupMenuButton<String>(
                          tooltip: 'Sort songs',
                          onSelected: (value) async {
                            setState(() => sort = value);
                            await loadAll();
                          },
                          itemBuilder: (_) =>
                              ['Title', 'Artist', 'Duration', 'Recent']
                                  .map(
                                    (s) =>
                                        PopupMenuItem(value: s, child: Text(s)),
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
            if (!allowed && !loading)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.library_music_outlined, size: 56),
                        const SizedBox(height: 16),
                        const Text(
                          'Let Svara find music on your phone.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => refresh(request: true),
                          child: const Text('Allow music access / Retry'),
                        ),
                        TextButton(
                          onPressed: () => ref
                              .read(libraryRepositoryProvider)
                              .openSettings(),
                          child: const Text('Open app settings'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (allowed && !loading && tracks.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text('Add music to your phone, then pull to refresh.'),
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
                              (t) => snapshot.data?.containsKey(t.id) ?? false,
                            )
                            .toList()
                          ..sort(
                            (a, b) => snapshot.data![b.id]!.compareTo(
                              snapshot.data![a.id]!,
                            ),
                          );
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
            if (more && allowed)
              SliverToBoxAdapter(
                child: TextButton(
                  onPressed: loadMore,
                  child: const Text('Load more music'),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class SongTile extends ConsumerWidget {
  const SongTile(this.track, {required this.onPlay, super.key});
  final Track track;
  final VoidCallback onPlay;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
    leading: TrackArt(track),
    title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      '${track.artist}${track.online ? ' • Audius' : ''}${track.streamable ? '' : ' • Restricted'}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    onTap: track.streamable
        ? onPlay
        : () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This track is restricted on Audius.'),
            ),
          ),
    trailing: PopupMenuButton<String>(
      tooltip: 'Song options',
      onSelected: (action) async {
        if (action == 'favorite') {
          await ref.read(favoritesProvider.notifier).toggle(track.id);
        }
        if (action == 'playlist' && context.mounted) {
          await addToPlaylist(context, ref, track);
        }
        if (action == 'queue' && track.streamable) {
          final h = ref.read(handlerProvider);
          final playing = h.player.playing;
          await h.setQueue(
            [...h.tracks, track],
            index: h.activeIndex,
            position: h.position,
            start: playing,
          );
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'favorite',
          child: Text(
            ref.watch(favoritesProvider).contains(track.id)
                ? 'Remove favorite'
                : 'Favorite',
          ),
        ),
        const PopupMenuItem(value: 'playlist', child: Text('Add to playlist')),
        if (track.streamable)
          const PopupMenuItem(value: 'queue', child: Text('Add to queue')),
      ],
    ),
  );
}
