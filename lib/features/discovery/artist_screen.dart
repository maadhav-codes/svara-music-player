import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/track.dart';
import '../../core/app_routes.dart';
import '../library/library_screen.dart';
import 'artist.dart';
import 'youtube_repository.dart';
import 'artist_favorites.dart';

class CatalogArtwork extends StatelessWidget {
  const CatalogArtwork(this.url, {this.size = 48, super.key});
  final String? url;
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: SizedBox(
      width: size,
      height: size,
      child: url == null
          ? ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.music_note),
            )
          : Image.network(
              url!,
              fit: BoxFit.cover,
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              errorBuilder: (_, _, _) => const Icon(Icons.music_note),
            ),
    ),
  );
}

class ArtistScreen extends ConsumerStatefulWidget {
  const ArtistScreen(this.artist, {super.key});
  final Artist artist;
  @override
  ConsumerState<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends ConsumerState<ArtistScreen> {
  late Artist artist = widget.artist;
  List<Track> tracks = [];
  List<MusicCollection> albums = [];
  bool loading = true, saving = false;
  String? error, metadataError;
  CancelToken? cancel;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    cancel?.cancel();
    final token = cancel = CancelToken();
    setState(() {
      loading = true;
      error = null;
      metadataError = null;
    });
    final repo = ref.read(youtubeProvider);
    String? warning, catalogWarning;
    try {
      final values = await Future.wait<Object>([
        repo.artistDetails(widget.artist, cancel: token).catchError((Object _) {
          warning = 'Artist details are unavailable. Showing search metadata.';
          return widget.artist;
        }),
        repo
            .search(
              '${widget.artist.name} songs',
              artist: widget.artist,
              cancel: token,
            )
            .catchError((Object _) {
              catalogWarning = 'Some catalog sections are unavailable.';
              return const YouTubePage([], null);
            }),
        repo
            .catalog(
              widget.artist.name,
              kind: 'albums',
              artist: widget.artist,
              cancel: token,
            )
            .catchError((Object _) {
              catalogWarning = 'Some catalog sections are unavailable.';
              return const CatalogPage();
            }),
      ]);
      if (!mounted || token.isCancelled) return;
      setState(() {
        metadataError = warning;
        error = catalogWarning;
        artist = values[0] as Artist;
        tracks = (values[1] as YouTubePage).tracks;
        albums = (values[2] as CatalogPage).collections;
      });
    } catch (_) {
      if (mounted && !token.isCancelled) {
        setState(() => error = 'Could not load the artist catalog.');
      }
    } finally {
      if (mounted && !token.isCancelled) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    cancel?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final following =
        ref
            .watch(followedArtistsProvider)
            .asData
            ?.value
            .any((a) => a.id == artist.id) ??
        false;
    return Scaffold(
      appBar: AppBar(title: Text(artist.name)),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CatalogArtwork(artist.artwork, size: 80),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          artist.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (artist.subscribers >= 0)
                          Text('${artist.subscribers} subscribers'),
                        FilledButton.tonalIcon(
                          onPressed: saving
                              ? null
                              : () async {
                                  setState(() => saving = true);
                                  try {
                                    await ref
                                        .read(followedArtistsProvider.notifier)
                                        .toggle(artist);
                                  } catch (_) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Could not save artist. Please retry.',
                                              ),
                                            ),
                                          );
                                    }
                                  } finally {
                                    if (mounted) setState(() => saving = false);
                                  }
                                },
                          icon: Icon(
                            following ? Icons.favorite : Icons.favorite_border,
                          ),
                          label: Text(
                            following ? 'Following' : 'Follow artist',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (artist.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  artist.description,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (metadataError != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(metadataError!),
              ),
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              TextButton(onPressed: load, child: Text('$error Retry')),
            const ListTile(title: Text('Top tracks')),
            if (!loading && error == null && tracks.isEmpty)
              const ListTile(title: Text('No attributed tracks found.')),
            for (var i = 0; i < tracks.length; i++)
              SongTile(
                tracks[i],
                onPlay: () =>
                    ref.read(handlerProvider).setQueue(tracks, index: i),
              ),
            const ListTile(title: Text('Albums')),
            if (!loading && error == null && albums.isEmpty)
              const ListTile(title: Text('No albums available.')),
            for (final album in albums) CollectionTile(album),
          ],
        ),
      ),
    );
  }
}

class CollectionTile extends StatelessWidget {
  const CollectionTile(this.collection, {super.key});
  final MusicCollection collection;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: CatalogArtwork(collection.artwork),
    title: Text(collection.name, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text(collection.artist),
    onTap: () => Navigator.push(
      context,
      AppPageRoute(builder: (_) => CollectionScreen(collection)),
    ),
  );
}

class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen(this.collection, {super.key});
  final MusicCollection collection;
  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  final tracks = <Track>[];
  String? next, error;
  bool loading = false;
  CancelToken? cancel;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (loading) return;
    final token = cancel = CancelToken();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final page = await ref
          .read(youtubeProvider)
          .collection(widget.collection, continuation: next, cancel: token);
      if (!mounted || token.isCancelled) return;
      setState(() {
        final ids = tracks.map((t) => t.id).toSet();
        tracks.addAll(page.tracks.where((t) => ids.add(t.id)));
        next = page.continuation;
      });
    } catch (_) {
      if (mounted && !token.isCancelled) {
        setState(() => error = 'Could not load this collection.');
      }
    } finally {
      if (mounted && !token.isCancelled) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    cancel?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.collection.name)),
    body: ListView(
      children: [
        for (var i = 0; i < tracks.length; i++)
          SongTile(
            tracks[i],
            onPlay: () => ref.read(handlerProvider).setQueue(tracks, index: i),
          ),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          TextButton(onPressed: load, child: Text('$error Retry')),
        if (!loading && next != null && error == null)
          TextButton(onPressed: load, child: const Text('Load more')),
        if (!loading && tracks.isEmpty && error == null)
          const ListTile(title: Text('No playable tracks in this collection.')),
      ],
    ),
  );
}
