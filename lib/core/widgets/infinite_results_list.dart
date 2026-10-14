import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A lazy list that prefetches from painted rows, excluding headers and cache.
class InfiniteResultsList extends StatefulWidget {
  const InfiniteResultsList({
    required this.itemCount,
    required this.itemBuilder,
    required this.loading,
    required this.hasMore,
    required this.onLoadMore,
    this.header,
    this.footer,
    this.canLoad = true,
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool loading, hasMore, canLoad;
  final VoidCallback onLoadMore;
  final Widget? header, footer;

  @override
  State<InfiniteResultsList> createState() => _InfiniteResultsListState();
}

class _InfiniteResultsListState extends State<InfiniteResultsList> {
  final _scroll = ScrollController();
  final _rows = GlobalKey();
  bool _checkScheduled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scheduleCheck);
  }

  void _scheduleCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!mounted ||
          widget.loading ||
          !widget.hasMore ||
          !widget.canLoad ||
          widget.itemCount == 0) {
        return;
      }
      final sliver = _rows.currentContext?.findRenderObject();
      if (sliver is! RenderSliverList) return;
      final end =
          sliver.constraints.scrollOffset +
          sliver.constraints.remainingPaintExtent;
      final threshold = (widget.itemCount * .8).ceil();
      // Only inspect the small set of materialized rows; never scan the data.
      for (
        var child = sliver.firstChild;
        child != null;
        child = sliver.childAfter(child)
      ) {
        final data = child.parentData! as SliverMultiBoxAdaptorParentData;
        final start = data.layoutOffset;
        if (start != null &&
            start < end &&
            start + child.size.height > sliver.constraints.scrollOffset &&
            data.index! + 1 >= threshold) {
          widget.onLoadMore();
          return;
        }
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleCheck();
    return CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: widget.header ?? const SizedBox.shrink()),
        SliverLayoutBuilder(
          builder: (context, constraints) {
            _scheduleCheck();
            return SliverList(
              key: _rows,
              delegate: SliverChildBuilderDelegate(
                widget.itemBuilder,
                childCount: widget.itemCount,
                addAutomaticKeepAlives: false,
              ),
            );
          },
        ),
        SliverToBoxAdapter(
          child: _PaginationStatus(
            loading: widget.loading,
            ended: widget.canLoad && !widget.hasMore && widget.itemCount > 0,
          ),
        ),
        SliverToBoxAdapter(child: widget.footer ?? const SizedBox.shrink()),
      ],
    );
  }
}

class _PaginationStatus extends StatefulWidget {
  const _PaginationStatus({required this.loading, required this.ended});
  final bool loading, ended;

  @override
  State<_PaginationStatus> createState() => _PaginationStatusState();
}

class _PaginationStatusState extends State<_PaginationStatus> {
  Timer? _reveal;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void didUpdateWidget(_PaginationStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loading != widget.loading) _update();
  }

  void _update() {
    _reveal?.cancel();
    _visible = false;
    if (widget.loading) {
      // Instant/cache responses never flash a spinner or delay the request.
      _reveal = Timer(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  @override
  void dispose() {
    _reveal?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    // Constant footer extent keeps the scroll geometry stable during fetches.
    height: 64,
    child: Center(
      child: widget.loading
          ? AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : widget.ended
          ? Text(
              'End of list',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : null,
    ),
  );
}
