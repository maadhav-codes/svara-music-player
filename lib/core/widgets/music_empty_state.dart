import 'package:flutter/material.dart';

class MusicEmptyState extends StatelessWidget {
  const MusicEmptyState({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.icon = Icons.music_note_rounded,
    super.key,
  });

  final String title, message, actionLabel;
  final VoidCallback onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: SizedBox(
              width: 144,
              height: 112,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 48,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 12,
                    child: Icon(Icons.auto_awesome, color: colors.primary),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 8,
                    child: Icon(Icons.music_note, color: colors.secondary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton(onPressed: onAction, child: Text(actionLabel)),
          if (secondaryActionLabel != null && onSecondaryAction != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onSecondaryAction,
              child: Text(secondaryActionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
