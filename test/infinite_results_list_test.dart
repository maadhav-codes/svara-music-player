import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svara/core/widgets/infinite_results_list.dart';

void main() {
  testWidgets(
    'prefetch at 80% of painted rows, guard pending fetch, preserve offset',
    (tester) async {
      var count = 100, calls = 0, built = 0;
      var loading = false, more = true;
      final response = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox.expand(
            child: StatefulBuilder(
              builder: (context, update) {
                return InfiniteResultsList(
                  itemCount: count,
                  header: const SizedBox(height: 200),
                  itemBuilder: (context, index) {
                    built++;
                    return SizedBox(height: 80, child: Text('Track $index'));
                  },
                  loading: loading,
                  hasMore: more,
                  onLoadMore: () async {
                    calls++;
                    update(() => loading = true);
                    await response.future;
                    update(() {
                      count += 20;
                      loading = false;
                      more = false;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(built, lessThan(20));
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      final viewport = scroll.position.viewportDimension;
      // Cache rows beyond the viewport must not trigger a request.
      scroll.jumpTo(200 + 79 * 80 - viewport);
      await tester.pumpAndSettle();
      expect(calls, 0);
      scroll.jumpTo(200 + 80 * 80 - viewport);
      await tester.pump();
      await tester.pump();
      expect(calls, 1);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 120));
      expect(calls, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final before = scroll.offset;
      response.complete();
      await tester.pumpAndSettle();
      expect(scroll.offset, before);
      expect(calls, 1);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('End of list'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Track 0'), findsNothing);
      expect(calls, 1);
    },
  );

  testWidgets('short pages fill viewport; errors pause automatic loading', (
    tester,
  ) async {
    var calls = 0;
    Future<void> render({required bool canLoad}) => tester.pumpWidget(
      MaterialApp(
        home: InfiniteResultsList(
          itemCount: 2,
          itemBuilder: (_, i) => SizedBox(height: 80, child: Text('$i')),
          loading: false,
          hasMore: true,
          canLoad: canLoad,
          onLoadMore: () => calls++,
        ),
      ),
    );
    await render(canLoad: false);
    await tester.pumpAndSettle();
    expect(calls, 0);
    await render(canLoad: true);
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets(
    'instant requests keep footer height and suppress spinner flash',
    (tester) async {
      var loading = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return InfiniteResultsList(
                itemCount: 1,
                itemBuilder: (_, _) => const SizedBox(height: 80),
                loading: loading,
                hasMore: false,
                onLoadMore: () {},
              );
            },
          ),
        ),
      );
      final spinner = find.byType(CircularProgressIndicator);
      final opacity = tester.widget<AnimatedOpacity>(
        find.ancestor(of: spinner, matching: find.byType(AnimatedOpacity)),
      );
      expect(opacity.opacity, 0);
      final scroll = tester.widget<CustomScrollView>(
        find.byType(CustomScrollView),
      );
      final extent = scroll.controller!.position.maxScrollExtent;
      update(() => loading = false);
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(scroll.controller!.position.maxScrollExtent, extent);
      // Disposal also cancels the delayed reveal timer.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );
}
