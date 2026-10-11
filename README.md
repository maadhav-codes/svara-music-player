# Svara 🎵

> **A minimal, private offline music library with Audius online discovery.**  
> No ads • No accounts • No tracking • No subscriptions • 100% Free & Open Source

---

## 📖 Overview

**Svara** (Sanskrit: _स्वर_, meaning _musical note_ or _voice_) is a lightweight, modern Android music player built with **Flutter & Material 3**.

It is designed for listeners who value **privacy, speed, and clean design**. Svara plays the music stored on your device and connects to **Audius** to let you explore fresh, streamable independent music—all without telemetry, accounts, or battery drain.

|                                **Library View**                                 |                                **Now Playing**                                |
| :-----------------------------------------------------------------------------: | :---------------------------------------------------------------------------: |
| <img src="docs/library-preview.png" width="300" alt="Library Screen Preview" /> | <img src="docs/player-preview.png" width="300" alt="Player Screen Preview" /> |

---

## ✨ Features

### 🎧 For Listeners

- **📱 Phone-Storage Library**: Automatically catalogs local audio files (MP3, AAC/M4A, FLAC, WAV, OGG) via native Android MediaStore.
- **🌐 Discover Independent Music**: Stream trending and searched independent tracks legally through the Audius catalog.
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
│   ├── discovery/              # Audius REST API repository and discovery screen
│   ├── player/                 # Shared audio engine (just_audio + audio_service)
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

Every commit and change is statically analyzed and tested:

```sh
# 1. Format check
dart format --output=none --set-exit-if-changed lib test

# 2. Static analysis
flutter analyze

# 3. Unit & Widget tests
flutter test
```

For hardware measurement guidelines and benchmarks, see [docs/VALIDATION.md](docs/VALIDATION.md).

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
- **Audius API Terms Compliance**: Online tracks are streamed directly via legal public endpoints. Online songs and audio are **never downloaded or cached to disk**. Audius metadata and artwork are kept strictly in volatile session memory.
- **No Cloud Backup**: `android:allowBackup="false"` is enforced to protect your personal listening habits from being uploaded to cloud backups.

---

## 📄 License & Attribution

- Released under the open-source MIT License.
- Music streamed through the Discover tab is provided by [Audius](https://audius.co) under the [Open Music License](https://audius.org/open-music-license.pdf).
