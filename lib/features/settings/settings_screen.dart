import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/media_source.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Make it yours',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 24),
        DropdownButtonFormField<ThemeMode>(
          initialValue: ref.watch(themeProvider),
          decoration: const InputDecoration(labelText: 'Appearance'),
          items: ThemeMode.values
              .map(
                (mode) => DropdownMenuItem(value: mode, child: Text(mode.name)),
              )
              .toList(),
          onChanged: (mode) {
            if (mode != null) {
              ref.read(themeProvider.notifier).set(mode);
            }
          },
        ),
        const SizedBox(height: 32),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('YouTube discovery and playback'),
          subtitle: const Text(
            'Experimental. Availability varies; phone music and Audius work when disabled.',
          ),
          value: ref.read(youtubeProvider).enabled,
          onChanged: (enabled) async {
            await ref.read(youtubeProvider).configure(enabled: enabled);
            if (!enabled &&
                ref.read(handlerProvider).current?.source ==
                    MediaSource.youtube) {
              await ref.read(handlerProvider).stop();
            }
            if (mounted) setState(() {});
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<StreamQuality>(
          initialValue: ref.read(youtubeProvider).quality,
          decoration: const InputDecoration(labelText: 'YouTube audio quality'),
          items: const [
            DropdownMenuItem(
              value: StreamQuality.dataSaver,
              child: Text('Data saver'),
            ),
            DropdownMenuItem(
              value: StreamQuality.standard,
              child: Text('Standard'),
            ),
            DropdownMenuItem(value: StreamQuality.high, child: Text('High')),
          ],
          onChanged: (quality) async {
            if (quality != null) {
              await ref.read(youtubeProvider).configure(quality: quality);
            }
          },
        ),
        const SizedBox(height: 32),
        const Text(
          'Private by design',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        const Text(
          'Your playlists, favorites, preferences, and listening history stay on this device. Svara has no ads, accounts, or analytics. Android backup is disabled.\n\nDiscover contacts the selected provider (Audius or YouTube) and artwork hosts. Streaming needs internet. Online audio is never saved for offline playback. Search metadata, artwork, and temporary playback URLs remain session-only. Saved YouTube selections retain their title and uploader label. No account cookies are used.',
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () async {
            await ref.read(storeProvider).db.delete('history');
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Listening history cleared')),
              );
            }
          },
          child: const Text('Clear listening history'),
        ),
        const SizedBox(height: 24),
        ...{
          'Audius API Terms': 'https://audius.co/documents/ApiTerms.pdf',
          'Audius Privacy Policy':
              'https://audius.co/documents/PrivacyPolicy.pdf',
          'Audius Terms of Use': 'https://audius.co/documents/TermsOfUse.pdf',
          'Open Music License': 'https://audius.org/open-music-license.pdf',
          'YouTube Terms': 'https://www.youtube.com/static?template=terms',
          'Google Privacy Policy': 'https://policies.google.com/privacy',
        }.entries.map(
          (entry) => TextButton(
            onPressed: () async {
              try {
                await ref.read(libraryRepositoryProvider).openUrl(entry.value);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'A web browser is needed to open this document.',
                      ),
                    ),
                  );
                }
              }
            },
            child: Text(entry.key),
          ),
        ),
        const Text(
          'Music provided by Audius is subject to its Terms of Use, API Terms, and the Open Music License. Available tracks vary; restricted tracks cannot be played.\n\nYouTube is an unofficial experimental source using NewPipeExtractor (GPL-3.0-or-later). YouTube terms restrict extraction; personal use and open-source distribution do not remove those restrictions. Svara does not promise a complete mainstream catalog.\n\nSvara 2.0 • Made for your music.',
        ),
        TextButton(
          onPressed: () =>
              showLicensePage(context: context, applicationName: 'Svara'),
          child: const Text('Open-source licenses'),
        ),
      ],
    ),
  );
}
