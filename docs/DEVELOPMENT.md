# Svara development guide

This guide covers architecture, tests, Android builds, and release maintenance. For installation and everyday use, see the [README](../README.md).

- [Setup](#setup)
- [Codebase guide](#codebase-guide)
- [Checks and tests](#checks-and-tests)
- [Build and release](#build-and-release)

Run commands from the repository root unless a step explicitly changes directories.

## Setup

Audius support has been removed. On upgrade, saved Audius references are removed from favorites, playlists, playback, and history. Local and YouTube entries and playlist names are preserved; playback position resets if the selected track was removed.

### Prerequisites

The existing project documentation identifies **Flutter 3.47.7** as the build baseline. The repository does not pin the Flutter SDK automatically. Use that version as the starting point for reproducing builds; newer SDKs may require migration.

| Tool             | Requirement                                                                        |
| ---------------- | ---------------------------------------------------------------------------------- |
| Flutter and Dart | Flutter 3.47.7; `pubspec.yaml` requires Dart `>=3.13.0 <4.0.0`                     |
| Java             | JDK 21 recommended; Java/Kotlin source targets are 17                              |
| Android SDK      | Platform API 36 and the build tools/NDK requested by Flutter and Gradle            |
| Device           | Android phone with USB debugging enabled, or an Android emulator                   |
| Network          | Needed initially for Dart packages, Gradle, Google/Maven repositories, and JitPack |

The app inherits compile, target, and minimum SDK versions from Flutter. Flutter 3.47.7 supplies compile/target API 36 and minimum API 24; the YouTube plugin explicitly uses compile API 36 and minimum API 24. Recheck these values when upgrading Flutter.

### Clone, check tools, and run

```sh
git clone https://github.com/maadhav-codes/svara-music-player.git
cd svara-music-player

flutter --version
flutter doctor -v
flutter doctor --android-licenses
flutter pub get
flutter devices
flutter run -d DEVICE_ID
```

Replace `DEVICE_ID` with an Android device ID from `flutter devices`. Resolve Android toolchain issues reported by `flutter doctor` before running. If Flutter selects the wrong Java installation, configure it with `flutter config --jdk-dir=/absolute/path/to/jdk-21`.

YouTube uses the local Android plugin and does not require a YouTube API key, Python, Deno, or a hosted backend. LRCLIB lookup has no configurable key in this implementation.

## Codebase guide

```text
lib/
├── main.dart                 # Opens SQLite, creates repositories and audio service
├── svara_app.dart            # Material 3 themes and Library/Discover/Playlists navigation
├── core/                    # Track/source models, Riverpod providers, SQLite, artwork
└── features/
    ├── library/             # Android MediaStore bridge, library filters and song options
    ├── discovery/           # YouTube search, ranked catalog contract and browse/search UI
    ├── player/              # Audio handler, source resolution, queue and player UI
    ├── playlists/           # Playlist persistence and management
    ├── lyrics/              # LRC parsing, LRCLIB lookup and lyrics UI
    └── settings/            # Theme, YouTube configuration, history and licenses
android/app/src/main/
├── AndroidManifest.xml      # Permissions, activity and background audio service
└── kotlin/app/svara/
    └── MainActivity.kt      # MediaStore, local artwork and lyrics-folder access
packages/svara_youtube/      # Dart method channel and native NewPipeExtractor plugin
test/                       # Unit and widget tests
integration_test/           # Live Android YouTube playback smoke test
assets/licenses/            # Bundled software license notices
```

Riverpod wires repositories and app state. SQLite (`sqflite`) holds durable data; Dio handles lyrics requests and the optional approved discovery catalog. `just_audio` plays audio, `audio_service` exposes background/media controls, and `audio_session` handles audio focus.

`Track.source` identifies local or YouTube tracks. `SvaraHandler` owns the logical queue, active index, shuffle, repeat, and persistence. Queues preserve every playable track without a size cap. `SvaraHandler` passes local URIs directly to the audio engine and resolves YouTube references at playback time. The audio engine receives one current source. On an online playback failure, the handler attempts one fresh resolution before pausing with queue and position preserved. Gapless transitions and next-track extraction prefetch are not implemented.

The YouTube plugin registers with both foreground and background Flutter engines. Native dependencies are pinned in `packages/svara_youtube/android/build.gradle`: NewPipeExtractor **v0.26.5**, OkHttp **4.12.0**, and NIO desugaring **2.1.5**. Artist searches use NewPipe’s music artist filter, albums use its music album filter, and radio searches use music playlists. Native requests use bounded workers, cancellation, and deadlines; transient repository requests retry at most twice.

YouTube song searches normally keep results between 45 seconds and 20 minutes and exclude likely non-music titles. Explicit mix, album, compilation, concert, or DJ-set searches use music video results and may allow long-form uploads up to four hours. An empty filtered page can still have a continuation. Tests cover this policy in Dart and Kotlin.

Custom route transitions, coordinated artwork heroes, and additional button micro-animations are deferred. See [motion architecture](MOTION.md).

## Checks and tests

Run these from the repository root:

```sh
# Check formatting without rewriting files.
dart format --output=none --set-exit-if-changed lib test integration_test packages/svara_youtube/lib

# Analyze Dart code.
flutter analyze

# Run the unit and widget suite in test/.
flutter test
```

The suite covers queue behavior, source resolution, discovery policies, library interactions, lyrics, player layouts, and gestures. Desktop tests use system SQLite through `sqflite_common_ffi`; a missing SQLite shared library must be resolved on the host.

To run the native YouTube search-policy tests on macOS/Linux after Flutter setup:

```sh
cd android
./gradlew :svara_youtube:testDebugUnitTest
cd ..
```

On Windows, use `gradlew.bat` instead of `./gradlew`.

### Live Android smoke test

This separate test needs an Android device, network access, and working YouTube extraction. It is not run by the normal `flutter test` command.

Use a dedicated test device: installation may replace the installed app, and version or signing conflicts may prompt an uninstall. Do not uninstall an installation containing data you need.

```sh
flutter test integration_test/youtube_device_test.dart -d DEVICE_ID

# Allow a longer window to check playback after pressing Home.
flutter test integration_test/youtube_device_test.dart -d DEVICE_ID --dart-define=BACKGROUND_SECONDS=15
```

The test searches Kevin MacLeod music, checks pagination, and uses Blender’s Big Buck Bunny as a muted playback fixture for resolution, decoding, seeking, progression, and saved-reference checks. For background verification, press Home when the log prints `BACKGROUND_READY`, then confirm the test passes. Reinstall the regular app afterward with `flutter run -d DEVICE_ID`; the test APK displays a test harness.

## Build and release

```sh
# Development APK.
flutter build apk --debug

# Universal release APK.
flutter build apk --release

# Smaller release APKs, one per architecture.
flutter build apk --release --split-per-abi
```

Build outputs are in `build/app/outputs/flutter-apk/`:

Keep generated APKs in the ignored build output directory. Local distribution APKs and checksum files are not kept in the workspace; `dist/` remains ignored. Flutter also generates the ignored Android `GeneratedPluginRegistrant.java`; it is not a second app implementation.

| Build             | Filename                                                                             |
| ----------------- | ------------------------------------------------------------------------------------ |
| Debug             | `app-debug.apk`                                                                      |
| Universal release | `app-release.apk`                                                                    |
| Split release     | `app-arm64-v8a-release.apk`, `app-armeabi-v7a-release.apk`, `app-x86_64-release.apk` |

Install a universal release on a connected test device with Android SDK’s `adb`:

```sh
adb -s DEVICE_ID install -r build/app/outputs/flutter-apk/app-release.apk
```

Release signing accepts `android/key.properties` for local builds:

```properties
storeFile=/absolute/path/to/svara-release.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=YOUR_KEY_ALIAS
keyPassword=YOUR_KEY_PASSWORD
```

The file and keystore are ignored by Git. All four values are required together.
Without signing configuration, local release builds use the debug key for
testing. Configure a production signing key before public distribution.
Release mode enables minification and resource shrinking.

Builds, checks, and release publishing are currently manual. CI/CD and GitHub
Actions workflows are not configured; automation will be added later.

Before public distribution:

1. Configure `android/key.properties` with a production keystore. Keep the keystore and passwords outside version control, and preserve the key for future updates.
2. Update `version` in `pubspec.yaml` (`versionName+versionCode`) and the displayed version in `lib/features/settings/settings_screen.dart`. Use a higher build number for upgrades; `--build-number=NUMBER` can override it during a build.
3. Run the checks above, the relevant Android smoke tests, and a minified release build. Confirm local playback, permissions, playlists, notification controls, and lyrics on a device.
4. Manually upload distribution APKs and their SHA-256 checksums to GitHub Releases. Ship corresponding app/plugin source, build instructions, and third-party notices with the distribution.

When updating NewPipeExtractor, review and pin the new version, update `assets/licenses/NOTICE.txt`, and verify native tests, live playback, and release shrinking. Preserve the plugin’s Rhino consumer R8 rules and NIO desugaring in both the app and plugin. The Gradle compatibility flags `android.builtInKotlin=false` and `android.newDsl=false` are currently enabled; revisit them when migrating the Android/Flutter toolchain.

## Storage and caching

The complete local library loads on refresh. Search, sorting, and filtering use that in-memory list. SQLite stores the library index, playlists (including Favorites), settings, history, and playback state. Older favorites are migrated on upgrade.

Search responses, fetched artwork, and online lyrics use a bounded session-memory cache utility. `YouTubeRepository` owns its search cache; `Store` handles durable data. Saved YouTube entries retain identifying titles and uploader labels. Resolved stream URLs and request headers are never persisted. The app has no persistent online-audio downloads or disk cache.

## Dependency notices

Flutter collects Dart package licenses automatically. `lib/core/licenses.dart` adds the bundled notices for native Gradle dependencies. Keep [native dependency notices](../assets/licenses/NOTICE.txt) and their license files alongside the corresponding dependencies when changing the build.

## Ranked discovery

Default builds use the official YouTube Top 100 Songs playlists for India and UK through the existing native extractor; no account, API key or backend is needed. Playlist IDs, title and owner channel are verified; exact video references replace cross-service matching. The earlier ListenBrainz audit is historical. Optional `--dart-define=DISCOVERY_CATALOG_URL=https://your-approved-host/v1` selects the approved-catalog contract instead. Secrets remain server-side.

The adapter fetches only aggregate rankings and recording IDs. Never send local history or follows. Each API client is serialized at 1.1-second intervals; observe Retry-After and rate-reset headers. Genre tags/artwork are supplementary data and are not part of this CC0 adapter. Country charts and recording-language/mood filters remain unsupported.

`RankedMatcher` makes at most two concurrent YouTube Music searches for a ten-entry page, preserves rank order, and rejects uncertain versions/recordings. The plugin retains the song-catalog result type and artist URL; canonical title/uploader remain separate from provider artists. Audio resolves only at playback. Do not broaden matching or add aliases without targeted tests and a relevance review.

### Isolated Android live checks

Use `SVARA_AUDIT_BUILD=true` to build `app.svara.audit` and preserve regular Svara storage. This changes the test application ID, not the source namespace or release version. Keep the phone unlocked while installing.

```sh
SVARA_AUDIT_BUILD=true flutter test integration_test/discovery_probe_test.dart -d DEVICE_ID
SVARA_AUDIT_BUILD=true flutter test integration_test/ranked_discovery_device_test.dart -d DEVICE_ID
python3 tools/run_android_smoke.py --device DEVICE_ID --adb /absolute/path/to/adb
```

The audit test samples 30 distinct identities across three reporting scopes, logs only public catalog/candidate metadata and checks muted decoding for accepted candidates. Review the output manually before reporting accuracy; automated acceptance is not the review. The smoke runner sends Home at the background marker and checks the existing fixture test’s continued playback. Store raw logs under ignored `docs/device-measurements/` or temporary paths; exclude stream URLs/headers and user data from published audit artifacts.
