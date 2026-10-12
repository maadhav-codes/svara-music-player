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
import 'ranked_discovery.dart';
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
  final ranked = <RecordingMatch>[];
  final searchController = TextEditingController();
  final searchFocus = FocusNode();
  late final matcher = RankedMatcher(ref.read(youtubeProvider));
  Timer? debounce;
  CancelToken? token;
  String query = '', mode = 'Songs';
  DiscoveryCategory? category;
  DiscoveryFilters filters = const DiscoveryFilters();
  BrowseCapabilities? capabilities;
  RankedPage? chart;
  DateTime? browseExpiresAt;
  String? error, continuation;
  bool loading = false, more = false;
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
    searchFocus.dispose();
    super.dispose();
  }

  void searchChanged(String value) {
    debounce?.cancel();
    token?.cancel();
    generation++;
    final wasBrowsing = query.isEmpty;
    setState(() {
      query = value.trim();
      if (wasBrowsing) mode = 'Songs';
      tracks.clear();
      artists.clear();
      ranked.clear();
      loading = false;
      error = null;
      more = false;
    });
    if (query.isEmpty) {
      load(reset: true);
    } else {
      debounce = Timer(
        const Duration(milliseconds: 350),
        () => load(reset: true),
      );
    }
  }

  Future<void> load({bool reset = false}) async {
    if (loading && !reset) return;
    if (reset) {
      token?.cancel();
      generation++;
      tracks.clear();
      artists.clear();
      ranked.clear();
      chart = null;
      browseExpiresAt = null;
      continuation = null;
      more = false;
    }
    final version = generation;
    final request = token = CancelToken();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final repo = ref.read(youtubeProvider);
      if (query.isEmpty) {
        final catalog = ref.read(discoveryCatalogProvider);
        if (!catalog.configured) return;
        final supported =
            capabilities ?? await catalog.capabilities(cancel: request);
        if (!mounted || generation != version) return;
        capabilities = supported;
        if (supported.markets.isEmpty) {
          throw const FormatException('No supported markets. Search above.');
        }
        if (!supported.markets.containsKey(filters.market)) {
          filters = DiscoveryFilters(
            market: supported.markets.keys.first,
            scope: filters.scope,
          );
        }
        if (supported.scopes.isNotEmpty &&
            !supported.scopes.containsKey(filters.scope)) {
          filters = DiscoveryFilters(
            market: filters.market,
            scope: supported.scopes.keys.first,
          );
        }
        final page = await catalog.page(
          market: filters.market,
          genre: category?.id,
          scope: filters.scope,
          cursor: continuation,
          cancel: request,
        );
        final matches = await matcher.matchPage(page, request);
        if (!mounted || generation != version) return;
        setState(() {
          chart = page;
          if (browseExpiresAt == null ||
              page.expiresAt.isBefore(browseExpiresAt!)) {
            browseExpiresAt = page.expiresAt;
          }
          final recordings = ranked.map((m) => m.recording.key).toSet();
          final videos = ranked
              .where((m) => m.track != null)
              .map((m) => m.track!.id)
              .toSet();
          for (final match in matches) {
            if (!recordings.add(match.recording.key)) continue;
            ranked.add(
              match.track != null && !videos.add(match.track!.id)
                  ? RecordingMatch(
                      match.recording,
                      reason: 'Duplicate playback recording',
                    )
                  : match,
            );
          }
          continuation = page.cursor;
          more = continuation != null;
        });
      } else if (mode == 'Artists') {
        final data = await repo.catalog(
          query,
          continuation: continuation,
          cancel: request,
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
          query,
          continuation: continuation,
          cancel: request,
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
        setState(
          () => error = query.isEmpty
              ? 'Could not load popular music. Please retry or search above.'
              : e.toString(),
        );
      }
    } finally {
      if (mounted && generation == version) setState(() => loading = false);
    }
  }

  Future<void> preferences() async {
    var market = filters.market;
    var scope = filters.scope;
    final supported = capabilities!;
    final value = await showModalBottomSheet<DiscoveryFilters>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Browse preferences',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  if (supported.markets.length > 1)
                    DropdownButtonFormField<String>(
                      key: ValueKey(market),
                      isExpanded: true,
                      initialValue: market,
                      decoration: const InputDecoration(
                        labelText: 'Chart market',
                      ),
                      items: supported.markets.entries
                          .map(
                            (m) => DropdownMenuItem(
                              value: m.key,
                              child: Text(m.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => update(() => market = value!),
                    ),
                  if (supported.scopes.length > 1)
                    DropdownButtonFormField<String>(
                      key: ValueKey(scope),
                      isExpanded: true,
                      initialValue: scope,
                      decoration: const InputDecoration(
                        labelText: 'Reporting period',
                      ),
                      items: supported.scopes.entries
                          .map(
                            (m) => DropdownMenuItem(
                              value: m.key,
                              child: Text(m.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => update(() => scope = value!),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      supported.preferenceDescription ?? 'The chart market does not filter recording language.',
                    ),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => update(() {
                          market = supported.markets.containsKey('in')
                              ? 'in'
                              : supported.markets.keys.first;
                          scope =
                              supported.scopes.isEmpty ||
                                  supported.scopes.containsKey('week')
                              ? 'week'
                              : supported.scopes.keys.first;
                        }),
                        child: const Text('Reset'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.pop(
                          context,
                          DiscoveryFilters(market: market, scope: scope),
                        ),
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (value != null && mounted) {
      filters = value;
      await load(reset: true);
    }
  }

  Future<void> playRanked(Track selected) async {
    if (browseExpiresAt == null || !browseExpiresAt!.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This chart is out of date. Refresh before playing.'),
        ),
      );
      return;
    }
    final queue = ranked.map((m) => m.track).whereType<Track>().toList();
    await ref
        .read(handlerProvider)
        .setQueue(queue, index: queue.indexWhere((t) => t.id == selected.id));
  }

  String dateLabel(DateTime value) =>
      value.toUtc().toIso8601String().substring(0, 10);
  String periodLabel(RankedPage page) =>
      page.periodStart == null || page.periodEnd == null
      ? 'Period unspecified'
      : '${dateLabel(page.periodStart!)} – ${dateLabel(page.periodEnd!.subtract(const Duration(seconds: 1)))}';

  @override
  Widget build(BuildContext context) {
    final browsing = query.isEmpty;
    final preferenceLabel =
        capabilities?.markets.length != null && capabilities!.markets.length > 1
        ? 'Browse preferences · ${capabilities!.markets[filters.market]}'
        : filters.scope == 'week'
        ? 'Browse preferences'
        : 'Browse preferences · ${capabilities?.scopes[filters.scope] ?? filters.scope}';
    final followed = ref.watch(followedArtistsProvider).asData?.value ?? [];
    final count = browsing
        ? ranked.length
        : mode == 'Artists'
        ? artists.length
        : tracks.length;
    return RefreshIndicator(
      onRefresh: () => load(reset: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search songs or artists',
                    suffixIcon: searchController.text.isEmpty
                        ? browsing && capabilities != null
                              ? IconButton(
                                  tooltip: preferenceLabel,
                                  icon: const Icon(Icons.tune_rounded),
                                  onPressed: preferences,
                                )
                              : null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              searchController.clear();
                              searchChanged('');
                            },
                          ),
                  ),
                  onChanged: searchChanged,
                ),
                SizedBox(height: browsing ? 16 : 12),
                if (!browsing)
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'Songs',
                        label: Text('Songs'),
                        icon: Icon(Icons.music_note),
                      ),
                      ButtonSegment(
                        value: 'Artists',
                        label: Text('Artists'),
                        icon: Icon(Icons.person),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (value) {
                      debounce?.cancel();
                      mode = value.single;
                      load(reset: true);
                    },
                  ),
                if (browsing) ...[
                  if (!ref.watch(discoveryCatalogProvider).configured) ...[
                    Text(
                      'Browse music',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Popular music and genre collections are not available yet. Search for a song or artist above.',
                    ),
                  ] else ...[
                    if (category != null)
                      TextButton.icon(
                        onPressed: () {
                          category = null;
                          load(reset: true);
                        },
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('All popular music'),
                      ),
                    Text(
                      category == null
                          ? capabilities == null
                                ? 'Popular music'
                                : capabilities!.browseTitle == null
                                ? 'Popular in ${capabilities!.markets[filters.market]}'
                                : '${capabilities!.browseTitle}${capabilities!.markets.length > 1 ? ' in ${capabilities!.markets[filters.market]}' : ''}'
                          : '${category!.label} · ${capabilities?.markets[filters.market] ?? filters.market.toUpperCase()}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (chart != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              chart!.sourceName.startsWith('YouTube Charts')
                                  ? '${chart!.sourceName} · Fetched ${chart!.fetchedAt.toLocal().toIso8601String().substring(0, 10)} ${chart!.fetchedAt.toLocal().toIso8601String().substring(11, 16)}'
                                  : '${chart!.sourceName} · ${capabilities?.scopes[chart!.scope] ?? 'Most played'} · ${periodLabel(chart!)} · Updated ${chart!.updatedAt == null ? 'unknown' : dateLabel(chart!.updatedAt!)}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                          if (chart!.chartUrl != null)
                            IconButton(
                              icon: const Icon(Icons.open_in_new, size: 16),
                              tooltip: 'Chart source',
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                              onPressed: () async {
                                try {
                                  await ref
                                      .read(libraryRepositoryProvider)
                                      .openUrl(chart!.chartUrl!);
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'A browser is needed to open the chart source.',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (category == null &&
                        capabilities != null &&
                        capabilities!.genres.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Browse genres',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) => Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final genre in capabilities!.genres)
                              SizedBox(
                                width: (constraints.maxWidth - 8) / 2,
                                child: OutlinedButton(
                                  onPressed: () {
                                    category = genre;
                                    load(reset: true);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: Text(genre.label),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ],
            ),
          ),
          if (browsing)
            for (final match in ranked)
              if (match.track != null)
                SongTile(match.track!, onPlay: () => playRanked(match.track!))
              else
                ListTile(
                  enabled: false,
                  leading: Text('${match.recording.rank}'),
                  title: Text(match.recording.title),
                  subtitle: Text(
                    '${match.recording.artists.isEmpty ? 'YouTube' : match.recording.artists.join(', ')} · ${match.reason}',
                  ),
                ),
          if (!browsing && mode == 'Songs')
            for (var i = 0; i < tracks.length; i++)
              SongTile(
                tracks[i],
                onPlay: () =>
                    ref.read(handlerProvider).setQueue(tracks, index: i),
              ),
          if (!browsing && mode == 'Artists')
            for (final artist in artists)
              ListTile(
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
              ),
          Padding(
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
                if (!loading &&
                    error == null &&
                    count == 0 &&
                    (!browsing ||
                        ref.read(discoveryCatalogProvider).configured))
                  MusicEmptyState(
                    title: browsing
                        ? 'No popular music available'
                        : mode == 'Artists'
                        ? 'No artists found'
                        : 'No songs found',
                    message:
                        'Try another song or artist in the search field above.',
                    actionLabel: 'Clear search',
                    icon: Icons.search_rounded,
                    onAction: () {
                      searchController.clear();
                      searchChanged('');
                    },
                  ),
                if (more && !loading && error == null)
                  OutlinedButton(
                    onPressed: load,
                    child: const Text('Load more'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
