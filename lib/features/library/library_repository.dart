import 'package:flutter/services.dart';

import '../../core/store.dart';
import '../../core/track.dart';

class LibraryRepository {
  LibraryRepository(
    this.store, {
    this.channel = const MethodChannel('app.svara/media'),
  });
  final Store store;
  final MethodChannel channel;
  Future<bool> permission({bool request = false}) async =>
      await channel.invokeMethod<bool>(
        request ? 'requestPermission' : 'hasPermission',
      ) ??
      false;
  Future<void> refresh() async {
    final known = <String, int>{};
    final version = await store.read('mediaVersion');
    for (var offset = 0; ; offset += 200) {
      final page = await store.tracks(offset: offset);
      for (final t in page) {
        known[t.id] = t.modified;
      }
      if (page.length < 200) break;
    }
    final result = Map<String, dynamic>.from(
      await channel.invokeMethod('scan', {'known': known, 'version': version})
          as Map,
    );
    if (result['unchanged'] == true) return;
    final changed = (result['changed'] as List)
        .map((j) => Track.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
    final ids = (result['ids'] as List).cast<String>().toSet();
    await store.reconcile(changed, ids);
    if (result['version'] != null) {
      await store.write('mediaVersion', result['version']);
    }
  }

  Future<List<Track>> page(int offset) => store.tracks(offset: offset);
  Future<Uint8List?> artwork(String uri) =>
      channel.invokeMethod<Uint8List>('artwork', {'uri': uri});
  Future<void> openSettings() => channel.invokeMethod('openSettings');
  Future<void> openUrl(String url) =>
      channel.invokeMethod('openUrl', {'url': url});
}
