/// YouTube does not expose recording language/genre labels. Match explicit
/// labels in returned titles/channel names, requiring every selected constraint.
class DiscoveryFilters {
  const DiscoveryFilters({this.language = '', this.genres = const {}});
  final String language;
  final Set<String> genres;
  static const languages = [
    '',
    'English',
    'Hindi',
    'Spanish',
    'Portuguese',
    'Tamil',
    'Telugu',
    'Korean',
    'Japanese',
    'Arabic',
    'French',
  ];
  static const genreOptions = [
    'Pop',
    'Rock',
    'Latin',
    'Jazz',
    'Classical',
    'Electronic',
    'Hip hop',
    'Folk',
    'Metal',
    'Lofi',
  ];
  bool get active => language.isNotEmpty || genres.isNotEmpty;
  String query(String query) => [
    query,
    language,
    ...(genres.toList()..sort()),
  ].where((s) => s.isNotEmpty).join(' ');
  String get label => [
    language,
    ...(genres.toList()..sort()),
  ].where((s) => s.isNotEmpty).join(' · ');
  bool matches(String title, String artist) {
    final metadata = '$title $artist'.toLowerCase();
    bool contains(String label) =>
        RegExp('(^|[^a-z])${RegExp.escape(label.toLowerCase())}([^a-z]|\$)')
            .hasMatch(metadata);
    return (language.isEmpty || contains(language)) && genres.every(contains);
  }
}
