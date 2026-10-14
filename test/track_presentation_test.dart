import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svara/core/track.dart';
import 'package:svara/core/track_presentation.dart';
import 'package:svara/features/library/library_screen.dart';

Track song(String title, {bool catalog = false}) => Track(
  id: 'youtube:aaaaaaaaaaa',
  title: title,
  artist: 'Aria - Topic',
  uri: 'https://www.youtube.com/watch?v=aaaaaaaaaaa',
  musicCatalogSong: catalog,
);

void main() {
  test('separates format and version without changing saved metadata', () {
    final track = song(
      'Aria - Quiet Song (Extended Remix) | Official Audio | Aria - Topic | HD',
      catalog: true,
    );
    final original = track.toSavedJson();
    final display = track.presentation;
    expect(display.title, 'Quiet Song');
    expect(display.versions, ['Extended Remix']);
    expect(display.labels, ['Audio', 'Songs catalog']);
    expect(track.toSavedJson(), original);
    expect(track.title, original['title']);
  });

  test(
    'preserves uncertain details, featured artists, and meaningful song names',
    () {
      for (final title in [
        'Live and Let Die',
        'Video Games',
        'Official Secrets',
        'Audio',
        'Live',
        'Song (From the Motion Picture)',
        'Song (feat. Another Artist)',
        'Song (An Unusual Phrase)',
        'Song Name Remix',
      ]) {
        expect(song(title).presentation.title, title, reason: title);
      }
      expect(
        song('Song | Movie Name | Unknown Label').presentation.title,
        'Song · Movie Name · Unknown Label',
      );
      final display = song(
        'Song (Live at Wembley) [2024 Remaster] (Instrumental)',
      ).presentation;
      expect(display.title, 'Song');
      expect(display.versions, [
        'Live at Wembley',
        '2024 Remaster',
        'Instrumental',
      ]);
      expect(
        song('Song (Live and Let Die)').presentation.title,
        'Song (Live and Let Die)',
      );
    },
  );

  test('declared official wording does not create an authenticity badge', () {
    final display = song('Song (Official Music Video) [4K]').presentation;
    expect(display.title, 'Song');
    expect(display.labels, ['Music video']);
    expect(display.labels.join(), isNot(contains('Official')));
    expect(display.labels, isNot(contains('Songs catalog')));
    expect(song('Song (Official Audio)').presentation.labels, ['Audio']);
  });

  test('local tags remain unchanged; empty cleanup falls back to original', () {
    const local = Track(
      id: 'local:1',
      title: 'Aria - Song (Remix) | Official Audio',
      artist: 'Aria',
      uri: 'content://music/1',
    );
    expect(local.presentation.title, local.title);
    expect(local.presentation.versions, isEmpty);
    expect(local.presentation.labels, isEmpty);
    expect(song('Aria - Topic').presentation.title, 'Aria - Topic');
    expect(
      song('[HD] (Official Audio)').presentation.title,
      '[HD] (Official Audio)',
    );
  });

  testWidgets(
    'row exposes variants and original title without changing play action',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final track = song(
        'Aria - Quiet Song (Extended Remix) | Official Audio',
        catalog: true,
      );
      var plays = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: SongTile(track, onPlay: () => plays++)),
          ),
        ),
      );
      expect(find.text('Quiet Song'), findsOneWidget);
      expect(find.text('Extended Remix'), findsOneWidget);
      expect(find.text('Songs catalog'), findsOneWidget);
      await tester.tap(find.text('Quiet Song'));
      expect(plays, 1);
      await tester.longPress(find.text('Quiet Song'));
      await tester.pumpAndSettle();
      expect(find.text('Original title'), findsOneWidget);
      expect(find.text(track.title), findsOneWidget);
      expect(plays, 1);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Extended Remix'), findsOneWidget);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
