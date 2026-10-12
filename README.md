# Svara

**Your phone’s music, plus YouTube discovery and streaming.** Svara is a free, open-source Android music player built with Flutter and Material 3.

Svara (स्वर) means “musical note” or “voice.” There are no ads, required accounts, subscriptions, or analytics. Your local music plays offline; online discovery, streaming, and lyrics lookup need an internet connection.

- **Users:** [Install Svara](#install-svara) → [Learn the basics](#using-svara).
- **Developers:** [Set up and run](#developer-quick-start) → [Development guide](docs/DEVELOPMENT.md).
- **Need help?** See [Troubleshooting](#troubleshooting).

## Preview

|                                         Library · Light                                          |                                            Library · Dark                                            |
| :----------------------------------------------------------------------------------------------: | :--------------------------------------------------------------------------------------------------: |
| <img src="docs/library-preview.png" width="300" alt="Svara local music library in light mode" /> | <img src="docs/library-preview-dark.png" width="300" alt="Svara local music library in dark mode" /> |

|                                      Now playing · Light                                      |                                        Now playing · Dark                                         |
| :-------------------------------------------------------------------------------------------: | :-----------------------------------------------------------------------------------------------: |
| <img src="docs/player-preview.png" width="300" alt="Svara full music player in light mode" /> | <img src="docs/player-preview-dark.png" width="300" alt="Svara full music player in dark mode" /> |

## Features at a glance

| Feature                 | What you can do                                                              |
| ----------------------- | ---------------------------------------------------------------------------- |
| Local library           | Search and browse songs by artist, album, folder, or recently played.        |
| Quick Mix               | Play a mix of local favorites and less recently played songs.                |
| Online discovery        | Search YouTube music, explore categories, and filter by language or genre.   |
| Artist follows          | Save artists locally and browse their tracks, releases, and radio playlists. |
| Playlists and favorites | Save local and online tracks, and reorder playlist tracks.                   |
| Playback                | Manage the queue, shuffle, repeat, and control playback in the background.   |
| Lyrics                  | Read timed or plain-text lyrics, including your own offline `.lrc` files.    |
| Personalization         | Choose light, dark, or system theme and set a sleep timer.                   |

**Supported platform:** Android only. The documented build targets Android 7.0+ (API 24+). There are no iOS, web, or desktop app targets, home-screen widgets, or downloads for online music.

Local format support depends on your device’s audio decoders. Common formats include MP3, AAC/M4A, FLAC, WAV, and OGG.

## Install Svara

Check the [GitHub Releases page](https://github.com/maadhav-codes/svara-music-player/releases) for published APKs. If no build is available, [build an APK from source](docs/DEVELOPMENT.md#build-and-release). Releases are manual; F-Droid distribution is planned and still needs a submission and build recipe.

1. Download an APK from a trusted maintainer onto your Android phone.
2. Open it and complete installation. Android may ask you to allow the app opening the APK to install unknown apps.
3. Open **Svara → Library**, tap **Allow music access / Retry**, and grant audio access.
4. Tap a song to play it, or open **Discover** to find online music.

If a release offers several APKs, choose `arm64-v8a` for most modern phones, `armeabi-v7a` for older 32-bit ARM phones, or `x86_64` for a matching emulator. A universal APK includes all supported architectures.

**Updating:** Install over the existing app to keep your saved data. The APK must use the same application ID (`app.svara`), signing key, and a suitable version code. Uninstalling or clearing app data removes playlists, favorites, settings, and history. Android cloud backup is disabled.

## Using Svara

### Find and play your music

Copy music onto your phone using USB or a file manager, then open **Library** and pull down to refresh or tap its refresh button. Svara reads Android’s media index; it does not import or duplicate your audio files.

- Browse **All**, **Artists**, **Albums**, **Folders**, or **Recently played**. Use search and sorting to find a song.
- Tap a song to play it, or tap **Quick Mix** to start a mix of local tracks.
- Open a song’s **⋮ Song options** menu to favorite it, add it to a playlist, play it next, add it to the queue, or view file details.

### Control playback

Tap the mini-player at the bottom of the screen to open the full player. There you can seek, skip tracks, shuffle, repeat, manage the queue, open lyrics, and set a sleep timer. Background playback includes media notification controls; playback pauses when headphones disconnect.

| Gesture                                                      | Action                                                     |
| ------------------------------------------------------------ | ---------------------------------------------------------- |
| Swipe left on the mini-player                                | Next track                                                 |
| Swipe right on the mini-player                               | Previous track, or restart after three seconds of playback |
| Swipe up on the mini-player                                  | Open the full player                                       |
| Swipe down in the full player when its content is at the top | Close the full player                                      |
| Swipe up on the full-player artwork                          | Open lyrics                                                |

The mini-player also has Play/Pause and Next buttons. Swiping down on it has no action. In the full player, tap **Sleep timer** for 15, 30, 45, or 60 minutes; choose **Turn off** to cancel.

### Save favorites and playlists

Tap the **heart** in the full player or choose **Favorite** from a song’s options. Find saved songs in **Playlists → Favorites**. Tap the heart again or use the removal option to unfavorite a song. Favorites is a built-in playlist and cannot be renamed or deleted.

To make a playlist:

1. Tap **Add to playlist** beside the heart in the full player, or **Add to Playlist** in a song’s options.
2. Choose an existing playlist or select **New playlist**, enter a name, and save. The song is added automatically.
3. Open **Playlists** to play and manage your collections, including reordering tracks.

Favorites and playlists survive app restarts. **Saving an online track stores a reference, not an audio download:** it still needs internet access and must remain available from the provider.

### Discover online music and artists

Open **Discover** and enter a search, or tap a category such as **Trending Today**, **Top Charts**, **Chill / Lofi**, **Workout**, **Pop**, or **Rock**. Tap **Load more** when available. Searches, results, and scroll positions remain available when switching tabs.

Use **Language** and **Genres** to narrow results. These filters match labels in titles and channel metadata; they do not detect the language of the audio. Combined filters require every selected label, so they can hide relevant songs. Category names describe suggested searches, not verified global charts.

To follow an artist, switch the search field’s **Songs / Artists** menu to Artists, open a profile, and tap **Follow artist**. Find suggestions in **Library → From your artists**, under Tracks, Releases, and Radios. Use its artist menu to reopen a profile and unfollow. Following stays on your phone and does not subscribe a YouTube account. Profiles and recommendations depend on the information available from the provider.

Choose audio quality in **Settings → Streaming & Discovery**: Data saver (64 kbps), Standard (128 kbps), or High (256 kbps). These are targets; the actual bitrate depends on the available stream.

The YouTube integration is unofficial and may stop working when YouTube changes. Restricted, removed, account-required, live, or unsupported videos may not play. Search cannot guarantee music-only results or correct artist attribution; a channel may belong to an uploader, cover artist, or remixer.

### Read lyrics, including offline files

Tap **Lyrics** in the full player or swipe up on its artwork. Timed lyrics follow playback; tap a line to seek. Plain-text lyrics appear when timed lyrics are unavailable.

For offline lyrics:

1. Place a UTF-8 `.lrc` file beside the matching audio file, for example `My Song.mp3` and `My Song.lrc`.
2. On Android 10+, open that song’s lyrics screen, tap **Choose song folder for .lrc**, and select the exact folder containing both files. Audio permission alone does not grant access to lyrics files.
3. Refresh lyrics if needed. Select other song folders separately, or select a folder again if access is revoked.

Example `.lrc` file:

```text
[00:12.00]First line of the song
[00:18.50]Next line of the song
```

Folder access is remembered using Android’s system folder picker. Files may include multiple timestamps per line and `[offset:...]` adjustments in milliseconds; the file size limit is 256 KiB.

A usable local lyrics file takes priority. Otherwise, Svara searches LRCLIB using the song’s title, artist, and, when available, album and duration. Accurate music tags help it find the right recording.

## Privacy and permissions

Svara stores its library index, favorites, playlists, settings, listening history, and playback state on your phone. Use **Settings → Clear listening history** to remove the history used by Quick Mix. Android cloud backup is disabled.

Online features contact YouTube, its stream/artwork hosts, and LRCLIB. These providers receive requests and normal network information; lyrics lookup sends song metadata. Local playback works without internet, but opening lyrics may trigger a lookup when a usable local file is unavailable.

| Access                  | Why Svara needs it                                                                                    |
| ----------------------- | ----------------------------------------------------------------------------------------------------- |
| Audio files             | Read your local music (`READ_MEDIA_AUDIO` on Android 13+, `READ_EXTERNAL_STORAGE` on older versions). |
| Internet                | Search, stream, fetch artwork, and look up lyrics.                                                    |
| Background playback     | Keep music playing through a foreground media service and wake lock.                                  |
| Notifications           | Show playback controls; visibility also depends on Android’s notification settings.                   |
| Selected lyrics folders | Read `.lrc` files in folders you choose through the system picker.                                    |

The app does not request camera, microphone, contacts, or unrestricted file access. Online audio is not downloaded for offline use, and resolved stream URLs and request headers are not saved.

## Developer quick start

Use **Flutter 3.47.7** as the documented build baseline; the repository does not automatically pin the Flutter SDK. `pubspec.yaml` requires Dart `>=3.13.0 <4.0.0`. You also need JDK 21 (recommended), Android SDK platform API 36 with the tools requested by Flutter/Gradle, and an Android device or emulator.

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

Replace `DEVICE_ID` with an Android device ID shown by `flutter devices`. Fix any Android toolchain issues reported by `flutter doctor` first. Initial setup needs network access for Dart and Gradle dependencies, including JitPack.

YouTube support uses the local `packages/svara_youtube` Android plugin with NewPipeExtractor. No YouTube API key, Python, Deno, or hosted backend is required. LRCLIB has no configurable API key in this app.

Run the standard checks from the repository root:

```sh
dart format --output=none --set-exit-if-changed lib test integration_test packages/svara_youtube/lib
flutter analyze
flutter test
```

Build a development APK with `flutter build apk --debug`. Find it at `build/app/outputs/flutter-apk/app-debug.apk`.

See the [development guide](docs/DEVELOPMENT.md) for the codebase map, storage and playback architecture, native tests, live Android smoke test, release signing, and publishing steps. **Public releases need a production signing key**; unconfigured local release builds use the debug key.

## Troubleshooting

| Problem                          | Try this                                                                                                                      |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Audio access is denied           | Tap **Allow music access / Retry**, or **Open app settings** and grant audio access.                                          |
| Songs are missing                | Confirm files are on the phone, then refresh Library. Android must index them; folders hidden with `.nomedia` may not appear. |
| A local song will not play       | Check that the file exists, permission is granted, and your device supports its encoding.                                     |
| Discover has no results          | Check connectivity, try another query, or loosen filters. An empty page may still offer **Load more**.                        |
| YouTube playback fails           | Retry or check for an app update. Provider restrictions or extractor changes can prevent playback.                            |
| Lyrics are missing or incorrect  | Check title/artist tags, or add a matching `.lrc` file and grant access to its exact folder.                                  |
| Gradle cannot fetch dependencies | Check the JDK, Android SDK, and network access to Google Maven, Maven Central, and JitPack.                                   |
| An APK will not update           | Check the signing key and version code. Uninstalling to resolve a conflict deletes app data.                                  |

When reporting a bug, include your Android and Svara versions, the steps to reproduce it, whether it affects local or YouTube playback, and the error shown. Developers should also include relevant logs with private information removed.

## License and credits

Svara is **GPL-3.0-or-later**. See [LICENSE](LICENSE) and [native dependency notices](assets/licenses/NOTICE.txt). In the app, open **Settings → Open-source licenses** for third-party notices.

Music and lyrics come from their respective providers. Their availability and permitted use depend on the provider and rights holder. The YouTube integration uses NewPipeExtractor and is not an official YouTube client.

Created by **Mayur Dayal** — [mayurdayal.engineer@gmail.com](mailto:mayurdayal.engineer@gmail.com).
