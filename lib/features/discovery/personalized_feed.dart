import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/track.dart';
import '../../core/app_routes.dart';
import 'artist.dart';
import 'youtube_repository.dart';
import 'artist_favorites.dart';
import 'artist_screen.dart';

class ArtistFeed {
  const ArtistFeed(this.tracks, this.albums, this.radios, this.failures);
  final List<Track> tracks;
  final List<MusicCollection> albums, radios;
  final int failures;
}

final artistFeedProvider = FutureProvider<ArtistFeed>((ref) async {
  final artists = await ref.watch(followedArtistsProvider.future);
  final token = CancelToken();
  ref.onDispose(token.cancel);
  final repo = ref.watch(youtubeProvider);
  final tracks = <Track>[],
      albums = <MusicCollection>[],
      radios = <MusicCollection>[];
  var failures = 0;
  // Three native requests per artist; process artists in sequence to respect the
  // extractor's bounded worker queue. A failing artist doesn't hide other feeds.
  for (final artist in artists) {
    if (token.isCancelled) break;
    try {
      final values = await Future.wait<Object>([
        repo
            .search('${artist.name} songs', artist: artist, cancel: token)
            .catchError((Object _) {
              failures++;
              return const YouTubePage([], null);
            }),
        repo
            .catalog(artist.name, kind: 'albums', artist: artist, cancel: token)
            .catchError((Object _) {
              failures++;
              return const CatalogPage();
            }),
        repo
            .catalog(
              '${artist.name} radio',
              kind: 'radios',
              artist: artist,
              cancel: token,
            )
            .catchError((Object _) {
              failures++;
              return const CatalogPage();
            }),
      ]);
      tracks.addAll(((values[0] as YouTubePage).tracks).take(5));
      albums.addAll(((values[1] as CatalogPage).collections).take(3));
      radios.addAll(((values[2] as CatalogPage).collections).take(3));
    } catch (_) {
      failures++;
    }
  }
  final seen = <String>{};
  return ArtistFeed(
    tracks.where((t) => seen.add(t.id)).toList(),
    albums,
    radios,
    failures,
  );
});

class PersonalizedFeed extends ConsumerStatefulWidget {
  const PersonalizedFeed({super.key});
  @override
  ConsumerState<PersonalizedFeed> createState() => _PersonalizedFeedState();
}

class _PersonalizedFeedState extends ConsumerState<PersonalizedFeed> {
  String kind = 'Tracks';
  @override
  Widget build(BuildContext context) {
    final artists = ref.watch(followedArtistsProvider).asData?.value ?? [];
    if (artists.isEmpty) return const SizedBox.shrink();
    final feed = ref.watch(artistFeedProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'From your artists',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Recommendation type',
                itemBuilder: (_) => [
                  'Tracks',
                  'Releases',
                  'Radios',
                ].map((s) => PopupMenuItem(value: s, child: Text(s))).toList(),
                onSelected: (value) => setState(() => kind = value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('$kind ▾'),
                ),
              ),
              PopupMenuButton<Artist>(
                tooltip: 'Followed artists',
                icon: const Icon(Icons.people_outline),
                itemBuilder: (_) => artists
                    .map((a) => PopupMenuItem(value: a, child: Text(a.name)))
                    .toList(),
                onSelected: (a) => Navigator.push(
                  context,
                  AppPageRoute(builder: (_) => ArtistScreen(a)),
                ),
              ),
            ],
          ),
          feed.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => TextButton(
              onPressed: () => ref.invalidate(artistFeedProvider),
              child: const Text('Retry recommendations'),
            ),
            data: (data) {
              final collections = kind == 'Releases'
                  ? data.albums
                  : data.radios;
              final count = kind == 'Tracks'
                  ? data.tracks.length
                  : collections.length;
              if (count == 0) {
                return TextButton(
                  onPressed: () => ref.invalidate(artistFeedProvider),
                  child: const Text('No recommendations found. Retry'),
                );
              }
              return Column(
                children: [
                  if (data.failures > 0)
                    TextButton(
                      onPressed: () => ref.invalidate(artistFeedProvider),
                      child: const Text(
                        'Some artist sections are unavailable. Retry',
                      ),
                    ),
                  SizedBox(
                    height: 128,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: count,
                      itemBuilder: (_, i) {
                        final track = kind == 'Tracks' ? data.tracks[i] : null;
                        final collection = track == null
                            ? collections[i]
                            : null;
                        return SizedBox(
                          width: 120,
                          child: InkWell(
                            onTap: () {
                              if (track != null) {
                                ref
                                    .read(handlerProvider)
                                    .setQueue(data.tracks, index: i);
                              } else {
                                Navigator.push(
                                  context,
                                  AppPageRoute(
                                    builder: (_) =>
                                        CollectionScreen(collection!),
                                  ),
                                );
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(right: 10, top: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CatalogArtwork(
                                    track?.artwork ?? collection?.artwork,
                                    size: 72,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    track?.title ?? collection!.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
