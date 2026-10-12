import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/track.dart';
import '../../core/app_routes.dart';
import '../../core/widgets/music_empty_state.dart';
import '../library/library_screen.dart';
import 'discovery_category.dart';
import 'discovery_filters.dart';
import 'artist.dart';
import 'artist_screen.dart';
import 'artist_favorites.dart';

class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});
  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  final tracks = <Track>[], artists = <Artist>[];
  final searchController = TextEditingController();
  Timer? debounce;
  CancelToken? token;
  String query = '', mode = 'Songs';
  DiscoveryCategory? category = DiscoveryCategory.trendingToday;
  DiscoveryFilters filters = const DiscoveryFilters();
  String? error, continuation;
  bool loading = false, more = true;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load(reset: true);
  }

  @override
  void dispose() {
    debounce?.cancel();
    token?.cancel();
    searchController.dispose();
    super.dispose();
  }

  Future<void> load({bool reset = false}) async {
    if (loading && !reset) return;
    if (reset) {
      token?.cancel();
      generation++;
      tracks.clear();
      artists.clear();
      more = true;
      continuation = null;
    }
    final version = generation;
    token = CancelToken();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final repo = ref.read(youtubeProvider);
      if (mode == 'Artists') {
        final data = await repo.catalog(
          query,
          continuation: continuation,
          cancel: token,
        );
        if (mounted && generation == version) {
          setState(() {
            final ids = artists.map((a) => a.id).toSet();
            artists.addAll(data.artists.where((a) => ids.add(a.id)));
            continuation = data.continuation;
            more = continuation != null;
          });
        }
      } else {
        final data = await repo.search(
          query.isNotEmpty ? query : category?.youtubeQuery ?? '',
          continuation: continuation,
          cancel: token,
          filters: filters,
        );
        if (mounted && generation == version) {
          setState(() {
            final ids = tracks.map((t) => t.id).toSet();
            tracks.addAll(data.tracks.where((t) => ids.add(t.id)));
            continuation = data.continuation;
            more = continuation != null;
          });
        }
      }
    } catch (e) {
      if (mounted &&
          generation == version &&
          !(e is DioException && CancelToken.isCancel(e))) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && generation == version) setState(() => loading = false);
    }
  }

  Future<void> genres() async {
    final selected = Set<String>.of(filters.genres);
    final value = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Match all selected genres',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final genre in DiscoveryFilters.genreOptions)
                      FilterChip(
                        label: Text(genre),
                        selected: selected.contains(genre),
                        onSelected: (on) => update(() {
                          if (on) {
                            selected.add(genre);
                          } else {
                            selected.remove(genre);
                          }
                        }),
                      ),
                  ],
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => update(selected.clear),
                      child: const Text('Clear'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, selected),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (value != null && mounted) {
      filters = DiscoveryFilters(
        language: filters.language,
        genres: Set.unmodifiable(value),
      );
      debounce?.cancel();
      await load(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = mode == 'Artists' ? artists.length : tracks.length;
    final followed = ref.watch(followedArtistsProvider).asData?.value ?? [];
    return RefreshIndicator(
      onRefresh: () => load(reset: true),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: count + 2,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: mode == 'Songs'
                          ? 'Search YouTube music'
                          : 'Search artists',
                      suffixIcon: PopupMenuButton<String>(
                        tooltip: 'Search type',
                        initialValue: mode,
                        itemBuilder: (_) => ['Songs', 'Artists']
                            .map((s) => PopupMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onSelected: (value) {
                          mode = value;
                          debounce?.cancel();
                          load(reset: true);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(mode),
                        ),
                      ),
                    ),
                    onChanged: (value) {
                      debounce?.cancel();
                      token?.cancel();
                      generation++;
                      query = value.trim();
                      category = query.isEmpty
                          ? DiscoveryCategory.trendingToday
                          : null;
                      setState(() {
                        loading = false;
                        tracks.clear();
                        artists.clear();
                        error = null;
                        more = false;
                      });
                      debounce = Timer(
                        const Duration(milliseconds: 350),
                        () => load(reset: true),
                      );
                    },
                  ),
                  if (mode == 'Songs')
                    Row(
                      children: [
                        Expanded(
                          child: PopupMenuButton<String>(
                            tooltip: 'Language',
                            itemBuilder: (_) => DiscoveryFilters.languages
                                .map(
                                  (l) => PopupMenuItem(
                                    value: l,
                                    child: Text(l.isEmpty ? 'Any language' : l),
                                  ),
                                )
                                .toList(),
                            onSelected: (value) {
                              filters = DiscoveryFilters(
                                language: value,
                                genres: filters.genres,
                              );
                              debounce?.cancel();
                              load(reset: true);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                '${filters.language.isEmpty ? 'Language' : filters.language} ▾',
                              ),
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: genres,
                          icon: const Icon(Icons.tune, size: 18),
                          label: Text(
                            filters.genres.isEmpty
                                ? 'Genres'
                                : filters.genres.join(' + '),
                          ),
                        ),
                      ],
                    ),
                  if (mode == 'Songs' && filters.active)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        'Matches all selected labels in title/channel metadata. Unlabeled recordings are omitted.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (query.isEmpty && mode == 'Songs')
                    SingleChildScrollView(
                      key: const ValueKey('discovery-categories'),
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final choice in DiscoveryCategory.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(choice.label),
                                selected: category == choice,
                                onSelected: (selected) {
                                  debounce?.cancel();
                                  category = selected
                                      ? choice
                                      : DiscoveryCategory.trendingToday;
                                  load(reset: true);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (query.isEmpty && mode == 'Songs')
                    Text(
                      'Suggested music search on YouTube',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            );
          }
          if (i <= count) {
            if (mode == 'Artists') {
              final artist = artists[i - 1];
              return ListTile(
                leading: CatalogArtwork(artist.artwork),
                title: Text(artist.name),
                subtitle: Text(
                  artist.description.isEmpty
                      ? 'YouTube Music artist'
                      : artist.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Icon(
                  followed.any((a) => a.id == artist.id)
                      ? Icons.favorite
                      : Icons.chevron_right,
                ),
                onTap: () => Navigator.push(
                  context,
                  AppPageRoute(builder: (_) => ArtistScreen(artist)),
                ),
              );
            }
            final track = tracks[i - 1];
            return SongTile(
              track,
              onPlay: () =>
                  ref.read(handlerProvider).setQueue(tracks, index: i - 1),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (loading) const CircularProgressIndicator(),
                if (error != null) Text(error!, textAlign: TextAlign.center),
                if (error != null)
                  TextButton(
                    onPressed: () => load(reset: true),
                    child: const Text('Retry'),
                  ),
                if (!loading && error == null && count == 0)
                  MusicEmptyState(
                    title: mode == 'Artists'
                        ? 'Search for an artist'
                        : query.isNotEmpty
                        ? 'No songs found'
                        : 'Find your next sound',
                    message: filters.active && mode == 'Songs'
                        ? 'No results carry all selected labels. Change the filters or load another page.'
                        : 'Try another search or explore trending music.',
                    actionLabel: 'Explore trending music',
                    icon: Icons.search_rounded,
                    onAction: () {
                      debounce?.cancel();
                      searchController.clear();
                      query = '';
                      mode = 'Songs';
                      filters = const DiscoveryFilters();
                      category = DiscoveryCategory.trendingToday;
                      load(reset: true);
                    },
                  ),
                if (more && !loading && error == null)
                  OutlinedButton(
                    onPressed: load,
                    child: const Text('Load more'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
