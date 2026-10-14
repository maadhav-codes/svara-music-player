import 'package:flutter/material.dart';

import '../track.dart';
import '../track_presentation.dart';

class TrackVersionLabels extends StatelessWidget {
  const TrackVersionLabels(
    this.presentation, {
    this.centered = false,
    super.key,
  });
  final TrackPresentation presentation;
  final bool centered;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 4,
    alignment: centered ? WrapAlignment.center : WrapAlignment.start,
    children: [
      for (final label in [...presentation.versions, ...presentation.labels])
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(label, style: Theme.of(context).textTheme.labelSmall),
          ),
        ),
    ],
  );
}

Future<void> showOriginalTrackTitle(BuildContext context, Track track) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Original title'),
        content: SingleChildScrollView(child: SelectableText(track.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
