# Changelog

All published Svara releases are listed below, newest first, including features, fixes, migrations, UI changes, tests, build changes, and documentation updates.

This history is reconstructed from published GitHub releases and the source changes between their Git tags. Dates are GitHub publication dates in **Asia/Kolkata (UTC+05:30)**. Build numbers come from each tag’s `pubspec.yaml`. Changes after the latest tag are listed as **Unreleased**. Historical features describe that version; Audius support was removed in v3.0.0.

## Release index

| Version                   | Released   | Android build number | Main changes                                                                       |
| ------------------------- | ---------- | -------------------- | ---------------------------------------------------------------------------------- |
| [3.0.0](#300--2026-10-12) | 2026-10-12 | 3000                 | Artist discovery and follows, YouTube-only streaming, library and storage overhaul |
| [2.2.0](#220--2026-10-12) | 2026-10-12 | 2200                 | Dedicated Favorites collection and warm light/dark themes                          |
| [2.1.1](#211--2026-10-12) | 2026-10-12 | 2101                 | Music-focused YouTube search and Settings improvements                             |
| [2.1.0](#210--2026-10-11) | 2026-10-11 | 2100                 | Lyrics, playback gestures, discovery categories, and responsive layouts            |
| [2.0.0](#200--2026-10-11) | 2026-10-11 | 2000                 | Experimental YouTube support, multi-source playback, and GPL licensing             |
| [1.0.0](#100--2026-10-11) | 2026-10-11 | 1                    | Initial local music player with Audius discovery                                   |

## Unreleased

### Tester feedback fixes

- Compacted Discover with an in-search filter action and grouped source metadata; spaced song rows, explicit 48px menu targets, and a thin mini-player progress line with subtle surface separation.

- Moved Quick Mix to Library options as “Mix my library”; hide followed-artist suggestions during local search/filtering.
- Separated Discover Browse and Search with clear-search and visible Songs/Artists selection; removed keyword language/genre filtering and preserved upstream search relevance.
- Removed generic Trending/Charts/mood presets. Prepared a bounded ranked-catalog adapter and strict YouTube recording matching with provider evidence retained separately. Official YouTube weekly Top 100 Songs playlists for India and UK replace the fan-heavy ListenBrainz default. Fixed chart/owner identity checks, exact playback IDs, source/fetch captions and snapshot pagination preserve regional chart order. Genre and language collections stay hidden.
- Moved player source attribution and Open in YouTube to Song options → Track Info.
- Show one top-level Create playlist action per loaded state, with Favorites intact and contextual New playlist retained.
- Added deterministic matching, cancellation, provider-error and playlist-state coverage; updated UI regression tests and light/dark previews.
- Completed a live Android audit of 30 source identities: 19 metadata-verified matches decoded, 11 conservatively unmatched, zero known incorrect substitutions in the reviewed sample. Added isolated audit installs and automated Home/background playback verification.

### Documentation

- Rewrote the README with a feature overview, installation instructions, everyday usage guides, privacy and permissions explanations, developer quick start, and troubleshooting.
- Removed the separate deferred-motion document.
- Added this changelog with all six published versions and an index of every commit in the available history.

## 3.0.0 — 2026-10-12

[Published release](https://github.com/maadhav-codes/svara-music-player/releases/tag/v3.0.0) · [Changes since v2.2.0](https://github.com/maadhav-codes/svara-music-player/compare/v2.2.0...v3.0.0) · Build **3000**

### Breaking changes and upgrade behavior

- Removed Audius discovery and streaming, its repository and providers, and the Audius source type. Playback now supports phone storage and YouTube.
- Automatically migrate the database from schema v1 to v2 to remove saved Audius references from favorites, playlists, playback state, and listening history.
- Preserve local and YouTube entries and playlist names. Reset the saved playback position if the selected track was removed.
- Migrate schema v2 to v3 to consolidate legacy `favorites` and `favoriteTracks` settings into the pinned Favorites playlist and normalize stored references.
- Remove the discovery provider selector and the Settings switch for enabling/disabling YouTube; retain YouTube audio quality selection.

### Added

- **Songs / Artists** search mode in Discover.
- Artist profiles with provider descriptions and subscriber information when available, attributed top search tracks, and albums.
- Playable album and radio collection views with pagination, backed by NewPipe music artist, album, and playlist filters.
- Persistent local artist follows with no account requirement, plus profile access and unfollow actions.
- **From your artists** on the Library home screen, with Tracks, Releases, and Radios from followed artists.
- Language selection and multiple genre filters. All selected labels must match title/channel metadata; these filters do not detect the language of the audio.
- `Artist`, `MusicCollection`, and followed-artist state models, native catalog methods, and repository support for the new discovery flows.

### Changed

- Load the entire local library on refresh instead of reading paginated SQLite chunks. Search, sorting, and filtering operate on the in-memory list.
- Remove the local-library **Load more** flow and redundant database reads during overlapping refreshes.
- Remove the 500-track queue window so the logical queue retains every playable track.
- Replace Library’s **Songs** filter with **All** and move Favorites access to the Playlists tab.
- Store Favorites alongside other playlists, replacing the separate favorites repository. Keep its built-in identity protected from renaming or deletion.
- Preserve discovery searches, results, and tab scroll positions when switching tabs through an `IndexedStack`.
- Replace separate cache implementations with a shared bounded LRU `MemoryCache` utility with expiry, capacity, and optional weight limits for artwork, lyrics, and YouTube search responses.
- Keep SQLite `Store` focused on durable data and let `YouTubeRepository` own its search cache.
- Resolve YouTube tracks directly through the audio handler’s callback, removing the intermediate `SourceResolver` layer.
- Remove unused track `artistId`, the unused YouTube metadata endpoint and associated uploader URL response fields, and the unused `path_provider` dependency.
- Use rounded-square artwork, remove decorative headers, and reduce the full-player Play button size.
- Remove the circular artwork progress indicator; playback progress remains in the seek bar and time labels.
- Remove unused artwork-derived color calculations from the player and keep the curated app theme consistent.
- Simplify responsive player sizing using layout constraints.
- Introduce the shared `AppPageRoute` wrapper; custom route transitions, artwork heroes, and additional button animations remain deferred.
- Update package and in-app version to **3.0.0**.

### Fixed

- Support `mailto:` and generic web links through the native URL handler.
- Show an error message when the Settings developer-contact action cannot open an email app.
- Correct a shell syntax error in `tools/measure_android.sh`.

### Build, tests, and documentation

- Add local release signing through ignored `android/key.properties`, with environment-variable overrides for keystore path/password and key alias/password.
- Require all four signing values together. Support `REQUIRE_RELEASE_SIGNING=true` to reject a release without production signing configuration; otherwise local release builds still fall back to the debug key.
- Add or update tests for artist searches/profiles, catalog browsing, follows, filters, database migrations, Favorites, caches, tab state, large queues, full-library loading, player layouts, source routing, and contact links.
- Update live YouTube smoke tests for the simplified source and stored-reference model.
- Document signing, manual releases, the absence of CI/CD workflows, migration behavior, full-library loading, Favorites storage, and artist discovery.
- Refresh light/dark library and player screenshots; ignore local distribution outputs in `dist/`.

## 2.2.0 — 2026-10-12

[Published release](https://github.com/maadhav-codes/svara-music-player/releases/tag/v2.2.0) · [Changes since v2.1.1](https://github.com/maadhav-codes/svara-music-player/compare/v2.1.1...v2.2.0) · Build **2200**

### Added

- Dedicated, built-in, non-deletable **Favorites** collection in Playlists, with playback and removal actions.
- Persistent playable favorite references for local, Audius, and YouTube tracks, plus recovery of legacy favorite IDs.
- **Add to playlist** button beside the heart in the full player. Creating a playlist from this action adds the current track automatically.
- Atomic favorite updates to protect stored state during rapid toggles, with saved references excluding signed stream URLs and artwork links.
- Dedicated `SvaraTheme` palettes: warm ivory and burnt-orange accents in light mode; charcoal and soft copper in dark mode.
- Component styles for navigation, chips, inputs, and bottom sheets, plus dark-mode preview screenshots.

### Changed

- Replace artwork-generated app palettes with curated colors for a consistent appearance.
- Match Android light/dark launch backgrounds to the new themes.
- Remove the `author` field from `pubspec.yaml` and format the Settings developer subtitle.
- Update package and in-app version to **2.2.0**.

### Tests and documentation

- Add coverage for mixed-source favorites, legacy recovery, rapid updates, and library favorite actions.
- Add theme contrast tests and refresh player-layout tests and light/dark screenshot generation.
- Overhaul the README with listener and developer navigation, usage guides, troubleshooting, privacy and Android permissions, source limitations, architecture, build commands, signing guidance, and release maintenance.

## 2.1.1 — 2026-10-12

[Published release](https://github.com/maadhav-codes/svara-music-player/releases/tag/v2.1.1) · [Changes since v2.1.0](https://github.com/maadhav-codes/svara-music-player/compare/v2.1.0...v2.1.1) · Build **2101**

### Changed

- Route ordinary YouTube searches to the music-song catalog, adding musical context to broad queries without changing the displayed query.
- Use music-video search for explicit mixes, albums, compilations, concerts, and DJ sets.
- Keep ordinary song results between 45 seconds and 20 minutes; allow explicitly requested long-form music up to four hours under the search policy.
- Exclude likely non-music titles such as gameplay, tutorials, podcasts, reviews, and reaction videos.
- Prioritize official-audio titles, VEVO uploads, and artist Topic channels.
- Change the search cache namespace to stop serving older generic-video results.
- Organize Settings into **Appearance**, **Streaming & Discovery**, **Privacy & Storage**, and **About**, with section headers, dividers, and descriptive subtitles.
- Display explicit quality targets in the YouTube dropdown: 64, 128, and 256 kbps.
- Add Mayur Dayal’s developer attribution and contact shortcut, package author metadata, and an updated native copyright notice.
- Update package and in-app version to **2.1.1**.

### Tests and documentation

- Add native `MusicSearchPolicy` unit tests and Dart coverage for duration bounds, noise filtering, official-audio ranking, and long-form intent.
- Use Kevin MacLeod music for live device search validation.
- Update the README with search policy, Settings, and developer details.

## 2.1.0 — 2026-10-11

[Published release](https://github.com/maadhav-codes/svara-music-player/releases/tag/v2.1.0) · [Changes since v2.0.0](https://github.com/maadhav-codes/svara-music-player/compare/v2.0.0...v2.1.0) · Build **2100**

### Added

- Synchronized and plain-text lyrics through LRCLIB, using title, artist, and available album/duration information to find a recording.
- Local `.lrc` sidecar lookup before online lookup, with Android Storage Access Framework folder selection and remembered folder access for scoped storage.
- LRC parsing with multiple timestamps per line, millisecond offsets, and a 256 KiB size limit.
- Full-screen lyrics with active-line highlighting, automatic scrolling, and tap-to-seek, accessible from the player button or an upward artwork swipe.
- Lyrics caching, refresh, plain-text fallback, and empty/error states.
- Mini-player swipes: left for next, right for previous/restart, and up to expand. Downward swipes dismiss the full player when its content is at the top.
- Haptic feedback and drag resistance, with gesture thresholds, cancellation handling, and reduced-motion/accessibility guards.
- Discovery categories: **Trending Today**, **Top Charts**, **Chill / Lofi**, **Workout**, **Pop**, and **Rock**.
- Audius category-specific genre/time feeds and YouTube search presets, with provider descriptions and horizontally scrolling category chips.
- Shared song-options bottom sheet for favorites, Add to Playlist, Play Next, Add to Queue, and track/file details, with optional artist/removal actions.
- Consistent `MusicEmptyState` views with actions such as Explore Discover and Create Playlist.

### Changed and fixed

- Pin Library filters while scrolling.
- Reset category state when entering a search and preserve category selection across provider switches.
- Improve discovery pagination and cancellation of stale results.
- Adapt the full player to landscape with artwork and controls side by side.
- Keep metadata and playback controls usable on compact displays and at larger text scales.
- Show a contrasting progress indicator in Play buttons while buffering or resolving a track.
- Prevent small drags, canceled gestures, and button taps from accidentally changing tracks.
- Update package version to **2.1.0** and refresh library/player screenshots and usage documentation.

### Tests

- Add lyrics parsing, caching, local-file, and lyrics-screen tests.
- Add mini-player gesture threshold, cancellation, reduced-motion, and accessibility tests.
- Add discovery category, pagination, stale-result, pinned-filter, song-menu, and empty-state tests.
- Add loading-indicator and responsive player-layout tests.

**Historical release-note correction:** The published v2.1.0 title and notes mention an Android home-screen widget. The tagged source contains no widget implementation or manifest registration, so this changelog does not count it as shipped. The current app also has no home-screen widget.

## 2.0.0 — 2026-10-11

[Published release](https://github.com/maadhav-codes/svara-music-player/releases/tag/v2.0.0) · [Changes since v1.0.0](https://github.com/maadhav-codes/svara-music-player/compare/v1.0.0...v2.0.0) · Build **2000**

### Added

- Experimental YouTube search and streaming using the local Android `svara_youtube` plugin and NewPipeExtractor **v0.26.5**.
- Discovery provider selection between Audius and YouTube, debounced YouTube search, pagination, and uploader attribution.
- YouTube enable/disable setting and Data saver, Standard, and High audio quality targets.
- Canonical YouTube links and source/video information actions.
- Source-aware track models and `SourceResolver` routing between local, Audius, and YouTube playback.
- On-demand stream resolution, with temporary URLs and request headers held in memory rather than durable queue/playlist storage.
- Playback failure recovery with one fresh/alternative resolution attempt before pausing, preserving the selected queue and playback state.
- Native bounded extraction workers, cancellation and deadlines, and plugin registration for foreground/background Flutter engines.
- In-app native dependency license registration and bundled notices for NewPipeExtractor and its dependencies.
- Live Android integration test covering YouTube search, pagination, stream resolution, decoding, seeking, playback progression, and saved references.

### Changed

- Adopt **GPL-3.0-or-later**, replacing the initial README’s MIT licensing declaration, and add the GPL license files.
- Rework the audio handler around a durable logical queue with a single active audio-engine source.
- Keep online artwork out of the background audio service’s persistent remote-artwork cache.
- Configure Android NIO desugaring, JitPack dependencies, and plugin consumer R8 rules; enable release minification and resource shrinking.
- Update package version to **2.0.0**, dependency configuration, architecture docs, YouTube limitations, and native notices.

### Fixed and tested

- Declare Android 13+ `POST_NOTIFICATIONS` permission.
- Register notification-icon metadata and add resource keep rules so notification and app icons survive release shrinking.
- Add/update source-routing, queue, YouTube repository, discovery UI, playback-recovery, and live-device tests.
- Update the Android measurement script for the new playback integration.

## 1.0.0 — 2026-10-11

[Published release](https://github.com/maadhav-codes/svara-music-player/releases/tag/v1.0.0) · [Initial source](https://github.com/maadhav-codes/svara-music-player/tree/v1.0.0) · Build **1**

### Initial features

- Android music player built with Flutter, Material 3, and Riverpod, with Library, Discover, Playlists, and Settings.
- Native MediaStore audio scanning and indexing, permission handling, local artwork, and generation-based change checks on supported Android versions.
- Local song search, sorting, paginated loading, and browsing by songs, albums, artists, folders, favorites, and recently played.
- Local audio playback using device-supported decoders through `just_audio`.
- Background audio and notification/lock-screen controls through `audio_service`, plus audio focus, interruption handling, and headphone-disconnection behavior through `audio_session`.
- Queue management, a bounded 500-track queue window, Play/Pause, previous/next, seeking, shuffle, repeat, and queue reordering.
- Favorites, custom playlists, playlist track reordering, and Quick Mix combining local favorites with less recently played tracks.
- Sleep timer options of 15, 30, 45, and 60 minutes.
- Audius trending/search discovery and streaming, rejecting gated or unavailable tracks, with session caching, request cancellation, and retry handling.
- Optional build-time Audius public API configuration.
- Artwork-derived colors, light/dark/system themes, and accessibility semantics.
- SQLite persistence for the local index, playlists, favorites, listening history, settings, and playback state.
- Local history clearing, no ads/accounts/analytics, disabled Android cloud backup, and scoped audio-file access.
- Session-memory artwork caching without offline downloads of online audio.

### Developer foundation

- Android project, Gradle wrapper, app and notification icons, launch theme, dependency lockfile, formatting/lint configuration, and ignored build/local files.
- Unit and widget tests using fake adapters and an in-memory database, including desktop SQLite test configuration.
- Android measurement helper script, library/player screenshots, and initial setup/build/privacy documentation.

## Commit index

Every commit reachable from the current branch is grouped below by the first release tag that contains it. This includes release-version bumps, smaller refactors, tests, and documentation commits. Tag annotations and changes to GitHub repository metadata are not source commits.

### Unreleased commits

- [ef1dba9](https://github.com/maadhav-codes/svara-music-player/commit/ef1dba972bfbfa9da8e007a8deeae267cfc03796) — docs: restructure README and add development guide

### 3.0.0 commits

- [0dfac74](https://github.com/maadhav-codes/svara-music-player/commit/0dfac748604f6da24baaf0fcf0b7a436c09db6da) — docs(readme): update release instructions and add signing configuration
- [98b85a7](https://github.com/maadhav-codes/svara-music-player/commit/98b85a7d6b18a28f780b4e725b928cc1e5c26db0) — refactor: remove Audius support and migrate to YouTube-only discovery
- [adb2ec1](https://github.com/maadhav-codes/svara-music-player/commit/adb2ec15d9c6e06d72ae502f4e4cdb14f0654dc1) — refactor: remove unused artistId field and metadata endpoint
- [e584093](https://github.com/maadhav-codes/svara-music-player/commit/e5840934f33a4d8c4dc25e41a86a77916c902124) — refactor(playlists): consolidate favorites into pinned playlist and extract memory cache
- [fafe78e](https://github.com/maadhav-codes/svara-music-player/commit/fafe78e70e8d876a79c4d008434ec29a223d1a44) — refactor(library): remove pagination and load full library into memory
- [9eb3855](https://github.com/maadhav-codes/svara-music-player/commit/9eb3855291c0d81e9384e28951febbf858d4f96f) — feat(discovery): add artist profiles, local follows, and catalog browsing
- [ed8ac53](https://github.com/maadhav-codes/svara-music-player/commit/ed8ac532778a5893855eff2253bf7aa7f11e8195) — chore(release): bump version to 3.0.0+3000

### 2.2.0 commits

- [bea9d51](https://github.com/maadhav-codes/svara-music-player/commit/bea9d5184a17d0b15dcff67b30a55f7ecee6dbd0) — docs(readme): overhaul documentation for v2.1 release
- [6568772](https://github.com/maadhav-codes/svara-music-player/commit/65687720419c01c55387f512b57b3a022b6e37c8) — chore: remove author field from pubspec and format settings subtitle
- [02939ba](https://github.com/maadhav-codes/svara-music-player/commit/02939baedc16ce50545adcd4a3d2bb82c0b87e87) — feat(favorites): implement dedicated Favorites collection with persistent references
- [6406b94](https://github.com/maadhav-codes/svara-music-player/commit/6406b942fcc71beb11e9ada25b757f4882ea71ca) — feat(theme): implement custom light/dark themes with warm ivory and copper accents
- [8c0d327](https://github.com/maadhav-codes/svara-music-player/commit/8c0d327884a53106a57989c8b7739556c0192dbf) — chore(release): bump version to 2.2.0+2200

### 2.1.1 commits

- [68e30c0](https://github.com/maadhav-codes/svara-music-player/commit/68e30c0e218a7e3c253e0a023a543b27cf7f4af4) — feat(youtube): implement music-focused search policy and filtering
- [72b18a4](https://github.com/maadhav-codes/svara-music-player/commit/72b18a4b3b16e631a4c97ab8af2ed5f8ff21bde5) — refactor(settings): redesign settings UI and update author metadata
- [2dce741](https://github.com/maadhav-codes/svara-music-player/commit/2dce74128efb0b81eb9e83c65fa71718907767dc) — chore(release): bump version to 2.1.1+2101

### 2.1.0 commits

- [671b789](https://github.com/maadhav-codes/svara-music-player/commit/671b7891718dff0e5f4c815c3f5c28ce84c627c9) — feat(lyrics): add synchronized lyrics with LRCLIB and local LRC support
- [f1b7c2c](https://github.com/maadhav-codes/svara-music-player/commit/f1b7c2c60bcc33cc47513a101fb5dbf6086033b4) — feat(player): add mini-player swipe gestures and full-player dismiss
- [e5acc51](https://github.com/maadhav-codes/svara-music-player/commit/e5acc51d151aaec2f53cab0449d74bcfc01db302) — feat(discovery): add browse categories and provider-specific feeds
- [f475f8d](https://github.com/maadhav-codes/svara-music-player/commit/f475f8dd129bb587be6aeea7794d567214560cf7) — feat(ui): unify empty states and streamline track interactions
- [afa1582](https://github.com/maadhav-codes/svara-music-player/commit/afa1582cfc897d089ddd6ae324498f437e5f6239) — refactor(player): implement responsive layout and enhance loading states
- [4e634a5](https://github.com/maadhav-codes/svara-music-player/commit/4e634a57fd7899491851d5ac72c1cd77755877d2) — chore(release): bump version to 2.1.0+2100

### 2.0.0 commits

- [8e7f293](https://github.com/maadhav-codes/svara-music-player/commit/8e7f293796e21997ef96315b7d293b7ac2fccc6f) — fix(android): ensure notification icon persists in release builds
- [fcd4489](https://github.com/maadhav-codes/svara-music-player/commit/fcd44894db90b37242df06f24f1efce01b46808f) — feat(discovery): add experimental YouTube integration and GPL-3.0 license

### 1.0.0 commits

- [2a02c12](https://github.com/maadhav-codes/svara-music-player/commit/2a02c120b9e47776e36c012df4a9082e28e4be9a) — feat(svara): initialize private offline music player with Audius discovery
