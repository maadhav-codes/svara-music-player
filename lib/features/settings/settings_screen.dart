import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
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
        const Text(
          'Private by design',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        const Text(
          'Your playlists, favorites, preferences, and listening history stay on this device. Svara has no ads, accounts, or analytics. Android backup is disabled.\n\nDiscover contacts Audius and artwork hosts when you use it. Streaming needs internet. Online audio is never saved for offline playback. Audius metadata and artwork caches last only for this session.',
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
          'Music provided by Audius is subject to its Terms of Use, API Terms, and the Open Music License. Available tracks vary; restricted tracks cannot be played.\n\nSvara 1.0 • Made for your music.',
        ),
      ],
    ),
  );
}
