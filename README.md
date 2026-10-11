# Svara 🎵

> **A minimal, private offline music library with Audius and experimental YouTube discovery.**
> No ads • No accounts • No tracking • No subscriptions • 100% Free & Open Source

---

## 📖 Overview

**Svara** (Sanskrit: _स्वर_, meaning _musical note_ or _voice_) is a lightweight, modern Android music player built with **Flutter & Material 3**.

It is designed for listeners who value **privacy, speed, and clean design**. Svara plays the music stored on your device and connects to **Audius** to let you explore fresh, streamable independent music—without telemetry or mandatory accounts. Online requests still reach the selected provider.

|                                **Library View**                                 |                                **Now Playing**                                |
| :-----------------------------------------------------------------------------: | :---------------------------------------------------------------------------: |
| <img src="docs/library-preview.png" width="300" alt="Library Screen Preview" /> | <img src="docs/player-preview.png" width="300" alt="Player Screen Preview" /> |

---

## ✨ Features

### 🎧 For Listeners

- **📱 Phone-Storage Library**: Automatically catalogs local audio files (MP3, AAC/M4A, FLAC, WAV, OGG) via native Android MediaStore.
- **🌐 Discover Independent Music**: Stream publicly accessible trending and searched tracks through the Audius catalog.
- **🎨 Dynamic Material 3 Design**: Adapts its color palette in real time to match the artwork of the currently playing track. Full support for Dark & Light modes.
- **⚡ Quick Mix**: A smart one-tap mix that weaves your favorites with songs you haven’t listened to recently.
- **📂 Flexible Browsing**: Seamlessly filter and browse your library by Songs, Albums, Artists, or Folders.
- **📜 Personal Playlists & Queue**: Build custom playlists, reorder songs on the fly with drag-and-drop, and manage playback queues effortlessly.
- **⏱️ Sleep Timer**: Fall asleep to your music with automatic shutdown timers (15, 30, 45, or 60 minutes).
- **🎛️ Audio Focus & Safety**: Automatically pauses when headphones or Bluetooth disconnect. Gently ducks volume during incoming notifications.
- **🔒 Private by Design**: Everything (listening history, favorites, playlists) stays strictly on your phone. No telemetry, no background analytics, no ads.

---

## 🚀 Quick Start (Developers)

### 1. Prerequisites

- **Flutter**: 3.47.7 stable or newer (Dart 3.13+)
- **JDK**: JDK 21 (recommended: Eclipse Temurin 21)
- **Android SDK**: Compile / Target **API 36**, Minimum **API 24** (Android 7.0+)

### 2. Clone & Run

```sh
# Clone the repository
git clone https://github.com/your-username/music-player-app.git
cd music-player-app

# Install dependencies
flutter pub get

# Run on a connected device or emulator
flutter run
```

### 3. Audius API Configuration (Optional)

The public read endpoints work out-of-the-box without credentials. You can optionally supply your own registered Audius public API key at build time:

```sh
flutter run --dart-define=AUDIUS_API_KEY=YOUR_PUBLIC_API_KEY
```

> [!NOTE]
> `AUDIUS_BASE_URL` defaults to `https://api.audius.co`. Do **not** inject private bearer tokens or secrets into client builds.

---

## 🛠️ Project Architecture

The app follows a feature-driven, clean architecture powered by **Riverpod**:

```text
lib/
├── core/                       # Shared models, persistent store, and utilities
│   ├── artwork.dart            # In-memory LRU artwork cache (8 MB limit)
│   ├── providers.dart          # Riverpod state notifiers (Theme, Favorites)
│   ├── store.dart              # SQLite database (settings, library index, history)
│   └── track.dart              # Universal Track model & queue algorithms
├── features/
│   ├── library/                # MediaStore repository, pagination, and local library UI
│   ├── discovery/              # Audius REST API, YouTube bridge repository, source selector
│   ├── player/                 # Logical queue, source resolver, shared audio engine
│   ├── playlists/              # On-device playlist repository and management UI
│   └── settings/               # Themes, privacy overview, and terms of service links
├── main.dart                   # Service initialization & provider registration
└── svara_app.dart              # Root Material 3 application & navigation shell
```

### Key Libraries

- **Audio Engine**: [`just_audio`](https://pub.dev/packages/just_audio) + [`audio_service`](https://pub.dev/packages/audio_service) + [`audio_session`](https://pub.dev/packages/audio_session)
- **State Management**: [`flutter_riverpod`](https://pub.dev/packages/flutter_riverpod)
- **Local Database**: [`sqflite`](https://pub.dev/packages/sqflite) (SQLite)
- **Networking**: [`dio`](https://pub.dev/packages/dio) with cancellation and exponential backoff

---

## 🧪 Verification & Testing

Run the deterministic checks before releasing:

```sh
# 1. Format check
dart format --output=none --set-exit-if-changed lib test integration_test packages/svara_youtube/lib

# 2. Static analysis
flutter analyze

# 3. Unit & Widget tests
flutter test
```

---

## 📦 Building Production APKs

To generate APKs for distribution:

```sh
# Build debug APK
flutter build apk --debug

# Build release APK
flutter build apk --release
```

Outputs are located in:  
`build/app/outputs/flutter-apk/app-release.apk`

> [!IMPORTANT]
> The repository currently signs release APKs with the local Android debug key for convenience. Before distributing to the Google Play Store or F-Droid, configure your own production keystore in `android/app/build.gradle.kts`.

---

## 🛡️ Privacy & Compliance

- **Scoped Storage**: Svara only requests `READ_MEDIA_AUDIO` (Android 13+) or `READ_EXTERNAL_STORAGE` (Android 12 and below). It never asks for contacts, cameras, microphones, or unrestricted storage access.
- **Online storage**: Audius uses public REST endpoints; YouTube uses unofficial extraction. Online songs and audio are **never downloaded or cached to disk**. Audius metadata and artwork are kept strictly in volatile session memory.
- **No Cloud Backup**: `android:allowBackup="false"` is enforced to protect your personal listening habits from being uploaded to cloud backups.

---

## 📄 License & Attribution

- Released under **GPL-3.0-or-later**, including the bundled NewPipeExtractor integration. See [LICENSE](LICENSE) and [native notices](assets/licenses/NOTICE.txt).
- Music streamed through the Discover tab is provided by [Audius](https://audius.co) under the [Open Music License](https://audius.org/open-music-license.pdf).

## Experimental YouTube integration

Discover has an Audius / YouTube selector. YouTube search is debounced and paginated; results identify the uploader and offer a canonical YouTube link. Settings can disable this source and select Data saver, Standard, or High audio quality. Disabling YouTube stops active YouTube playback while preserving the queue.

The local Flutter plugin at `packages/svara_youtube` registers on every engine, including the background service engine. It pins **NewPipeExtractor v0.26.5**, **OkHttp 4.12.0**, and **desugar_jdk_libs_nio 2.1.5**. Gradle needs internet access to Maven repositories and JitPack. No YouTube API key, private credentials, Python, Deno, or hosting server is required by this implementation. Network/parser work runs on two native workers with a bounded queue and cancellation/deadlines; transient requests retry at most twice.

`Track.source` distinguishes local, Audius, and YouTube references. Existing local/Audius records are read without changing their IDs. One audio player receives only the current resolved stream. The handler owns shuffle, repeat, navigation, and queue edits. Each online selection is resolved at playback time; signed URLs and headers are never persisted. YouTube titles/uploader labels from user-selected queues and playlists are saved for identification, with current metadata refreshed on playback. Audius saved records retain reference-only placeholders. Search/artwork caches remain bounded and session-only.

On a playback failure, the handler tries one fresh resolution (an alternative supported format for YouTube) before pausing with the queue and position preserved. Restricted, account-required, removed, or unsupported videos produce useful messages. Live videos and non-progressive/unsupported delivery formats are currently excluded. Gapless transitions across the logical queue are not guaranteed; there is no next-track extraction prefetch or persistent audio download/cache.

YouTube extraction is **unofficial and experimental**. It can break when YouTube changes and does not guarantee all mainstream music. Personal use and GitHub distribution do not waive [YouTube terms](https://www.youtube.com/static?template=terms). An official visible-player integration has different restrictions and does not provide an authorized raw-audio/background replacement. Software licenses do not grant recording rights.

### Live Android smoke test

Use a dedicated test device or back up Svara data first. Flutter's installer may uninstall an existing application when its version/signature conflicts. Check the installed build number and use a higher `--build-number` where required; do not allow uninstall on a device with data you need.

```sh
flutter test integration_test/youtube_device_test.dart -d DEVICE_ID
# Optional longer window for a manual HOME/background check:
flutter test integration_test/youtube_device_test.dart -d DEVICE_ID --dart-define=BACKGROUND_SECONDS=15
```

The live test uses Blender's Big Buck Bunny, plays muted, checks search/pagination, audio decoding, seeking, queue serialization, and progression. It is excluded from normal unit-test CI. For background verification, send HOME during `BACKGROUND_READY`, then check that the test completes. Afterward rebuild/install the regular app: the test APK is a harness, not the normal UI.

### Updating and distributing

Pin a reviewed extractor release in `packages/svara_youtube/android/build.gradle`, update notices, and rerun unit tests, the live device check, and a minified release build. The app uses the existing legacy Kotlin Gradle compatibility flags; Flutter warns these will need migration in a future SDK update. Consumer R8 rules retain Rhino classes; minimum API 24 requires NIO core-library desugaring in both app and plugin.

Release APKs are currently **development-signed**, even in release mode. Configure a production signing key before public distribution, preserve that key for upgrades, and publish corresponding app/plugin source, build instructions, and third-party notices alongside your APK. Do not publish cookies, signing keys, signed stream URLs, or music files. Keep local playback usable when extraction is unavailable.

### Synchronized lyrics

Tap **Lyrics** in the full player or swipe up on its artwork. Svara shows line-synchronized LRCLIB lyrics, with tap-to-seek and plain-text fallback. Local `.lrc` sidecars take priority and work offline. On Android 10+, choose the exact song folder once from the lyrics screen to grant access to text sidecars. See [lyrics setup and validation](docs/LYRICS.md) for formats, caching, privacy and Android storage details.

### Mini-player gestures

Swipe left on the mini-player for Next, right for Previous, and up to open the full player. Tapping still opens the player, and the Play/Pause and Next buttons remain available. Previous uses the same behavior as the full-player control: restart after three seconds of playback, otherwise select the previous queue item. Small drags and downward swipes on the mini-player do nothing. Artwork and text follow horizontal drags with resistance and ease back on release; reduced-motion settings disable this movement. A subtle selection haptic fires when a swipe actually selects another queue item. In the full player, swipe down while its content is at the top to close it; scrolling, seeking and the upward lyrics gesture remain available.

### Discover categories

When search is empty, tap **Trending Today**, **Top Charts**, **Chill / Lofi**, **Workout**, **Pop**, or **Rock** to explore without typing. Chips stay visible while results load in one horizontally scrollable row, including with larger text. Audius starts with Trending Today selected; the provider and actual time range appear in a subtle sub-header. Typing returns to normal search; clearing the field restores browse suggestions. Category selection follows source switching, refresh, retry and pagination.

Audius uses genre-filtered weekly trending for Lo-Fi, Pop and Rock, and a music search for Workout. Its Trending Today shortcut shows weekly trending and Top Charts shows monthly trending, with the actual range labeled below the heading; these are Audius rankings rather than global daily charts. YouTube categories launch labeled suggested music searches. Provider ranges and genre filters follow the [official Audius documentation](https://docs.audius.co/sdk/tracks/).
