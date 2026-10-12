import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svara/core/store.dart';
import 'package:svara/features/discovery/youtube_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Inspect official regional chart playlists', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Text('Svara discovery audit running'),
      ),
    );
    final store = await Store.open(path: ':memory:');
    final youtube = YouTubeRepository(store);
    try {
      for (final country in ['IN', 'GB']) {
        final data = await youtube.musicCharts(country);
        debugPrint(
          'SVARA_REGION_CHART ${jsonEncode({'country': country, 'name': data['name'], 'ownerName': data['ownerName'], 'ownerUrl': data['ownerUrl'], 'sourceUrl': data['sourceUrl'], 'count': (data['tracks'] as List).length})}',
        );
        for (final track in (data['tracks'] as List).take(15)) {
          debugPrint(
            'SVARA_REGION_ENTRY ${jsonEncode({'country': country, ...Map<String, dynamic>.from(track as Map)})}',
          );
        }
        expect(data['country'], country);
        expect(data['tracks'] as List, isNotEmpty);
      }
    } finally {
      await store.db.close();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
