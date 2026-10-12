import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svara/core/theme.dart';

double contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return first > second
      ? (first + 0.05) / (second + 0.05)
      : (second + 0.05) / (first + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    test(
      '$brightness keeps text and active controls legible on app surfaces',
      () {
        final theme = SvaraTheme.build(brightness);
        final c = theme.colorScheme;
        final pairs = <(Color, Color)>[
          (c.onPrimary, c.primary),
          (c.onPrimaryContainer, c.primaryContainer),
          (c.onSecondary, c.secondary),
          (c.onSecondaryContainer, c.secondaryContainer),
          (c.onTertiary, c.tertiary),
          (c.onTertiaryContainer, c.tertiaryContainer),
          (c.onError, c.error),
          (c.onErrorContainer, c.errorContainer),
          (c.onInverseSurface, c.inverseSurface),
          (c.inversePrimary, c.inverseSurface),
          for (final surface in [
            c.surface,
            c.surfaceContainerLowest,
            c.surfaceContainerLow,
            c.surfaceContainer,
            c.surfaceContainerHigh,
            c.surfaceContainerHighest,
          ]) ...[
            (c.onSurface, surface),
            (c.onSurfaceVariant, surface),
            (c.primary, surface),
          ],
        ];
        for (final pair in pairs) {
          expect(
            contrast(pair.$1, pair.$2),
            greaterThanOrEqualTo(4.5),
            reason: 'Text contrast for ${pair.$1} on ${pair.$2}',
          );
        }
        expect(contrast(c.outline, c.surface), greaterThanOrEqualTo(3));
        expect(theme.scaffoldBackgroundColor, c.surface);
        expect(theme.navigationBarTheme.indicatorColor, Colors.transparent);
        expect(
          theme.navigationBarTheme.iconTheme!.resolve({
            WidgetState.selected,
          })!.color,
          c.primary,
        );
      },
    );
  }
}
