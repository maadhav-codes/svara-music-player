import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/media_source.dart';
import '../../core/track.dart';
import '../library/library_screen.dart';
import 'discovery_category.dart';

class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});
  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  final List<Track> tracks = [];
  Timer? debounce;
  CancelToken? token;
  String query = '';
  DiscoveryCategory? category = DiscoveryCategory.trendingToday;
  String? error;
  bool loading = false, more = true;
  int generation = 0;
  MediaSource source = MediaSource.audius;
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
      final List<Track> page;
      String? nextContinuation;
      bool hasMore;
      final preset = query.isEmpty ? category : null;
      if (source == MediaSource.youtube) {
        final data = await ref
            .read(youtubeProvider)
            .search(
              query.isNotEmpty ? query : preset?.youtubeQuery ?? '',
              continuation: continuation,
              cancel: token,
            );
        page = data.tracks;
        nextContinuation = data.continuation;
        hasMore = data.continuation != null;
      } else {
        page = await ref
            .read(audiusProvider)
            .tracks(
              query: query.isNotEmpty ? query : preset?.audiusQuery ?? '',
              genre: preset?.genre,
              time: preset?.time,
              offset: tracks.length,
              cancel: token,
            );
        hasMore = page.length == 30;
      }
      if (mounted && generation == version) {
        setState(() {
          final ids = tracks.map((t) => t.id).toSet();
          tracks.addAll(page.where((t) => ids.add(t.id)));
          continuation = nextContinuation;
          more = hasMore;
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

  Future<void> artist(Track t) async {
    if (t.source == MediaSource.youtube) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.artist,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'YouTube uploader • Channel attribution may differ from the recording artist. This may be a cover, remix, or live performance.',
                ),
                TextButton(
                  onPressed: () => openSource(t),
                  child: const Text('Open video in YouTube'),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    if (t.artistId == null) return;
    try {
      final data = await ref.read(audiusProvider).artist(t.artistId!);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['name']?.toString() ?? t.artist,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text('@${data['handle'] ?? ''} • Audius'),
                const SizedBox(height: 16),
                Text(
                  data['bio']?.toString() ?? 'No artist biography available.',
                ),
                const SizedBox(height: 16),
                Text('${data['follower_count'] ?? 0} followers'),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> openSource(Track track) async {
    try {
      await ref.read(libraryRepositoryProvider).openUrl(track.sourceUrl);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'A browser or YouTube app is needed to open this video.',
            ),
          ),
        );
      }
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
                Text(
                  source == MediaSource.audius
                      ? 'Powered by Audius • Independent music, streamed online. Catalog availability varies.'
                      : 'YouTube • Experimental source. Availability varies; extraction may stop working. Uploader names may differ from artists.',
                ),
                const SizedBox(height: 16),
                SegmentedButton<MediaSource>(
                  segments: const [
                    ButtonSegment(
                      value: MediaSource.audius,
                      label: Text('Audius'),
                    ),
                    ButtonSegment(
                      value: MediaSource.youtube,
                      label: Text('YouTube'),
                    ),
                  ],
                  selected: {source},
                  onSelectionChanged: (value) {
                    debounce?.cancel();
                    source = value.single;
                    if (query.isEmpty &&
                        category == null &&
                        source == MediaSource.audius) {
                      category = DiscoveryCategory.trendingToday;
                    }
                    unawaited(load(reset: true));
                  },
                ),
                const SizedBox(height: 24),
                TextField(
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search ${source.label}',
                  ),
                  onChanged: (value) {
                    debounce?.cancel();
                    token?.cancel();
                    generation++;
                    query = value.trim();
                    category = query.isEmpty && source == MediaSource.audius
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
                                      : source == MediaSource.audius
                                      ? DiscoveryCategory.trendingToday
                                      : null;
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
                      : query.isEmpty && source == MediaSource.audius
                      ? 'Trending this week'
                      : 'Search results',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (query.isEmpty && category != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    source == MediaSource.audius
                        ? category!.audiusDescription
                        : 'Suggested music search on YouTube',
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
          return Column(
            children: [
              SongTile(
                t,
                onPlay: () {
                  final playable = tracks.where((s) => s.streamable).toList();
                  unawaited(
                    ref
                        .read(handlerProvider)
                        .setQueue(playable, index: playable.indexOf(t)),
                  );
                },
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => artist(t),
                  child: Text(
                    t.source == MediaSource.youtube
                        ? 'Uploader / Open video'
                        : 'About artist',
                  ),
                ),
              ),
            ],
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
                Text(
                  source == MediaSource.youtube &&
                          query.isEmpty &&
                          category == null
                      ? 'Choose a category or search YouTube to find music. Phone music remains available offline in Library.'
                      : 'No tracks found. Try another search.',
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
