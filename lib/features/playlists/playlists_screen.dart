import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/track.dart';
import '../../core/widgets/music_empty_state.dart';
import '../library/library_screen.dart';
import 'playlists_repository.dart';

Future<String?> playlistName(
  BuildContext context, {
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Name your playlist'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 60,
        decoration: const InputDecoration(hintText: 'A little evening music'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  // Dispose after the closing animation releases the text field.
  Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
  return value;
}

Future<void> addToPlaylist(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final repo = PlaylistsRepository(ref.read(storeProvider));
  final lists = await repo.all();
  if (!context.mounted) return;
  final id = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Add to playlist')),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('New playlist'),
            onTap: () => Navigator.pop(context, 'new'),
          ),
          ...lists.map(
            (p) => ListTile(
              title: Text(p.name),
              subtitle: Text('${p.tracks.length} tracks'),
              onTap: () => Navigator.pop(context, p.id),
            ),
          ),
        ],
      ),
    ),
  );
  if (id == null || !context.mounted) return;
  if (id == 'new') {
    final name = await playlistName(context);
    if (name == null) return;
    lists.add(
      Playlist(DateTime.now().microsecondsSinceEpoch.toString(), name, [track]),
    );
  } else {
    final i = lists.indexWhere((p) => p.id == id);
    final p = lists[i];
    if (!p.tracks.any((t) => t.id == track.id)) {
      lists[i] = Playlist(p.id, p.name, [...p.tracks, track]);
    }
  }
  await repo.save(lists);
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved to playlist')));
  }
}

class PlaylistsScreen extends ConsumerStatefulWidget {
  const PlaylistsScreen({this.onLibrary, super.key});
  final VoidCallback? onLibrary;
  @override
  ConsumerState<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends ConsumerState<PlaylistsScreen> {
  List<Playlist> lists = [];
  PlaylistsRepository get repo => PlaylistsRepository(ref.read(storeProvider));
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final value = await repo.all();
    if (mounted) setState(() => lists = value);
  }

  Future<void> createPlaylist() async {
    final name = await playlistName(context);
    if (name == null || !mounted) return;
    lists.add(
      Playlist(DateTime.now().microsecondsSinceEpoch.toString(), name, []),
    );
    await repo.save(lists);
    await load();
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: load,
    child: ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Keep a feeling.',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text('Personal playlists, saved on your phone.'),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: createPlaylist,
                icon: const Icon(Icons.add),
                label: const Text('New playlist'),
              ),
            ],
          ),
        ),
        if (lists.isEmpty)
          MusicEmptyState(
            title: 'Make room for your favorites',
            message:
                'Create a playlist, then add songs from their three-dot menu.',
            actionLabel: 'Create playlist',
            onAction: createPlaylist,
            icon: Icons.queue_music,
          ),
        ...lists.map(
          (p) => ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 8,
            ),
            leading: const Icon(Icons.queue_music, size: 36),
            title: Text(p.name),
            subtitle: Text('${p.tracks.length} tracks'),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      PlaylistDetail(p, onLibrary: widget.onLibrary),
                ),
              );
              await load();
            },
            trailing: PopupMenuButton<String>(
              tooltip: 'Playlist options',
              onSelected: (action) async {
                if (action == 'delete') {
                  lists.removeWhere((item) => item.id == p.id);
                } else {
                  final name = await playlistName(context, initial: p.name);
                  if (name == null) return;
                  final i = lists.indexOf(p);
                  lists[i] = Playlist(p.id, name, p.tracks);
                }
                await repo.save(lists);
                await load();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class PlaylistDetail extends ConsumerStatefulWidget {
  const PlaylistDetail(this.playlist, {this.onLibrary, super.key});
  final VoidCallback? onLibrary;
  final Playlist playlist;
  @override
  ConsumerState<PlaylistDetail> createState() => _PlaylistDetailState();
}

class _PlaylistDetailState extends ConsumerState<PlaylistDetail> {
  late List<Track> tracks = List.of(widget.playlist.tracks);
  Future<void> save() async {
    final repo = PlaylistsRepository(ref.read(storeProvider));
    final lists = await repo.all();
    final i = lists.indexWhere((p) => p.id == widget.playlist.id);
    if (i >= 0) {
      lists[i] = Playlist(widget.playlist.id, widget.playlist.name, tracks);
      await repo.save(lists);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.playlist.name)),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: tracks.isEmpty
                ? null
                : () => ref
                      .read(handlerProvider)
                      .setQueue(tracks.where((t) => t.streamable).toList()),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Play playlist'),
          ),
        ),
        Expanded(
          child: tracks.isEmpty
              ? SingleChildScrollView(
                  child: MusicEmptyState(
                    title: 'Every playlist starts with a song',
                    message: 'Find music in Library and use Add to Playlist from a song’s menu.',
                    actionLabel: widget.onLibrary != null
                        ? 'Browse Library'
                        : 'Back to playlists',
                    onAction: () {
                      Navigator.pop(context);
                      widget.onLibrary?.call();
                    },
                    icon: Icons.playlist_add,
                  ),
                )
              : ReorderableListView.builder(
                  itemCount: tracks.length,
                  onReorderItem: (a, b) async {
                    setState(
                      () =>
                          tracks = moveQueueItem(tracks, a, b > a ? b + 1 : b),
                    );
                    await save();
                  },
                  itemBuilder: (_, i) => Row(
                    key: ValueKey(tracks[i].id),
                    children: [
                      Expanded(
                        child: SongTile(
                          tracks[i],
                          removeLabel: 'Remove from playlist',
                          onRemove: () async {
                            setState(() => tracks.removeAt(i));
                            await save();
                          },
                          onPlay: () => ref
                              .read(handlerProvider)
                              .setQueue(tracks, index: i),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: Icon(Icons.drag_handle),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    ),
  );
}
