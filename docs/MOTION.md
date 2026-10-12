# Deferred motion phase

`lib/core/app_routes.dart` provides the shared `AppPageRoute` entry point for
player, settings, playlist, artist, and collection navigation. It currently uses
Flutter's platform transitions. UI density, accessibility, filtering, and artist
persistence take priority over new animation behavior.

When implementing motion:

- Add custom route transitions in `AppPageRoute` and honor
  `MediaQuery.disableAnimations` and accessible navigation.
- Coordinate artwork heroes using stable track/provider IDs. Avoid duplicate
  hero tags across the three permanently mounted tabs and the mini-player.
- Add subtle button feedback while preserving loading states, 48dp touch
  targets, and the existing playback gestures.
- Test portrait, landscape, text scaling, reduced motion, interrupted navigation,
  and restoring a tab's scroll/search state before enabling the new transitions.

Custom page animations and hero transitions are intentionally deferred.
