import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/track.dart';
import '../../core/widgets/music_empty_state.dart';
import '../library/library_screen.dart';
import 'discovery_category.dart';

class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});
  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  final List<Track> tracks = [];
  final searchController = TextEditingController();
  Timer? debounce;
  CancelToken? token;
  String query = '';
  DiscoveryCategory? category = DiscoveryCategory.trendingToday;
  String? error;
  bool loading = false, more = true;
  int generation = 0;
  String? continuation;
  @override
  void initState() {
    super.initState();
    unawaited(load(reset: true));
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
      final preset = query.isEmpty ? category : null;
      final data = await ref
          .read(youtubeProvider)
          .search(
            query.isNotEmpty ? query : preset?.youtubeQuery ?? '',
            continuation: continuation,
            cancel: token,
          );
      final page = data.tracks;
      if (mounted && generation == version) {
        setState(() {
          final ids = tracks.map((t) => t.id).toSet();
          tracks.addAll(page.where((t) => ids.add(t.id)));
          continuation = data.continuation;
          more = data.continuation != null;
        });
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

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () => load(reset: true),
    child: ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: tracks.length + 2,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'A new sound\nawaits.',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text('Search and stream music from YouTube.'),
                const SizedBox(height: 24),
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search YouTube',
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
                      error = null;
                      more = false;
                    });
                    debounce = Timer(
                      const Duration(milliseconds: 350),
                      () => load(reset: true),
                    );
                  },
                ),
                if (query.isEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Find your next sound',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    key: const ValueKey('discovery-categories'),
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: DiscoveryCategory.values
                          .map(
                            (choice) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(choice.label),
                                selected: category == choice,
                                onSelected: (selected) {
                                  debounce?.cancel();
                                  category = selected
                                      ? choice
                                      : DiscoveryCategory.trendingToday;
                                  unawaited(load(reset: true));
                                },
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  query.isEmpty && category != null
                      ? category!.label
                      : 'Search results',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (query.isEmpty && category != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Suggested music search on YouTube',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          );
        }
        if (i <= tracks.length) {
          final t = tracks[i - 1];
          return SongTile(
            t,
            onPlay: () {
              final playable = tracks.where((s) => s.streamable).toList();
              unawaited(
                ref
                    .read(handlerProvider)
                    .setQueue(playable, index: playable.indexOf(t)),
              );
            },
          );
        }
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              if (loading) const CircularProgressIndicator(),
              if (error != null) Text(error!, textAlign: TextAlign.center),
              if (error != null)
                TextButton(
                  onPressed: () => load(reset: true),
                  child: const Text('Retry'),
                ),
              if (!loading && error == null && tracks.isEmpty)
                MusicEmptyState(
                  title: query.isNotEmpty
                      ? 'No songs found'
                      : 'Find your next sound',
                  message: 'Try another search or explore trending music here in Discover.',
                  actionLabel: 'Explore trending music',
                  icon: Icons.search_rounded,
                  onAction: () {
                    debounce?.cancel();
                    searchController.clear();
                    query = '';
                    category = DiscoveryCategory.trendingToday;
                    unawaited(load(reset: true));
                  },
                ),
              if (more && !loading && error == null)
                OutlinedButton(onPressed: load, child: const Text('Load more')),
            ],
          ),
        );
      },
    ),
  );
}
