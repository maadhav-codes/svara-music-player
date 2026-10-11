import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/track.dart';
import '../library/library_screen.dart';

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
  String? error;
  bool loading = false, more = true;
  int generation = 0;
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
    }
    final version = generation;
    token = CancelToken();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final page = await ref
          .read(audiusProvider)
          .tracks(query: query, offset: tracks.length, cancel: token);
      if (mounted && generation == version) {
        setState(() {
          tracks.addAll(page);
          more = page.length == 30;
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
                const Text(
                  'Powered by Audius • Independent music, streamed online. Catalog availability varies.',
                ),
                const SizedBox(height: 24),
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search Audius',
                  ),
                  onChanged: (value) {
                    debounce?.cancel();
                    token?.cancel();
                    generation++;
                    query = value.trim();
                    debounce = Timer(
                      const Duration(milliseconds: 400),
                      () => load(reset: true),
                    );
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  query.isEmpty ? 'Trending this week' : 'Search results',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
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
                  child: const Text('About artist'),
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
                const Text('No tracks found. Try another search.'),
              if (more && !loading && error == null)
                OutlinedButton(onPressed: load, child: const Text('Load more')),
            ],
          ),
        );
      },
    ),
  );
}
