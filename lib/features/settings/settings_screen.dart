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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentQuality = ref.watch(youtubeProvider).quality;
    final isYoutubeEnabled = ref.watch(youtubeProvider).enabled;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // --- Appearance ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              'Appearance',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Theme'),
            subtitle: Text(ref.watch(themeProvider).name.capitalize()),
            trailing: DropdownButton<ThemeMode>(
              value: ref.watch(themeProvider),
              underline: const SizedBox(),
              items: ThemeMode.values
                  .map(
                    (mode) => DropdownMenuItem(
                      value: mode,
                      child: Text(mode.name.capitalize()),
                    ),
                  )
                  .toList(),
              onChanged: (mode) {
                if (mode != null) {
                  ref.read(themeProvider.notifier).set(mode);
                }
              },
            ),
          ),
          const Divider(indent: 24, endIndent: 24),

          // --- Streaming & Discovery ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              'Streaming & Discovery',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.travel_explore_outlined),
            title: const Text('YouTube discovery'),
            subtitle: const Text(
              'Experimental source. Stream audio and music search.',
            ),
            value: isYoutubeEnabled,
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
          if (isYoutubeEnabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: DropdownButtonFormField<StreamQuality>(
                initialValue: currentQuality,
                decoration: const InputDecoration(
                  labelText: 'YouTube audio quality',
                  prefixIcon: Icon(Icons.high_quality_outlined),
                ),
                items: StreamQuality.values
                    .map(
                      (quality) => DropdownMenuItem(
                        value: quality,
                        child: Text(quality.label),
                      ),
                    )
                    .toList(),
                onChanged: (quality) async {
                  if (quality != null) {
                    await ref.read(youtubeProvider).configure(quality: quality);
                    if (mounted) setState(() {});
                  }
                },
              ),
            ),
          const Divider(indent: 24, endIndent: 24),

          // --- Privacy & Storage ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              'Privacy & Storage',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.security_outlined),
            title: const Text('Private by design'),
            subtitle: const Text(
              'No ads, accounts, or analytics. Your playlists and listening history stay strictly on your phone.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Clear listening history'),
            subtitle: const Text('Remove recently played tracks from Quick Mix'),
            onTap: () async {
              await ref.read(storeProvider).db.delete('history');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Listening history cleared')),
                );
              }
            },
          ),
          const Divider(indent: 24, endIndent: 24),

          // --- About & Developer ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              'About',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Svara'),
            subtitle: const Text('Version 2.1.1 • 100% Free & Open Source'),
          ),
          ListTile(
            leading: const Icon(Icons.code_outlined),
            title: const Text('Developer'),
            subtitle: const Text('Mayur Dayal • mayurdayal.engineer@gmail.com'),
            onTap: () async {
              try {
                await ref
                    .read(libraryRepositoryProvider)
                    .openUrl('mailto:mayurdayal.engineer@gmail.com');
              } catch (_) {}
            },
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Open-source licenses'),
            subtitle: const Text('GPL-3.0 and third-party dependencies'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                showLicensePage(context: context, applicationName: 'Svara'),
          ),
        ],
      ),
    );
  }
}

extension on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

extension on StreamQuality {
  String get label => switch (this) {
    StreamQuality.dataSaver => 'Data saver (64 kbps)',
    StreamQuality.standard => 'Standard (128 kbps)',
    StreamQuality.high => 'High (256 kbps)',
  };
}
