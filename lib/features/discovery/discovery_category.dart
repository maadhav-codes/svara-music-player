/// Suggested YouTube music searches, separate from typed search text.
enum DiscoveryCategory {
  trendingToday('Trending Today', youtubeQuery: 'trending music today'),
  topCharts('Top Charts', youtubeQuery: 'top songs music charts'),
  chill('Chill / Lofi', youtubeQuery: 'chill lofi music'),
  workout('Workout', youtubeQuery: 'workout music'),
  pop('Pop', youtubeQuery: 'pop music'),
  rock('Rock', youtubeQuery: 'rock music');

  const DiscoveryCategory(this.label, {required this.youtubeQuery});
  final String label;
  final String youtubeQuery;
}
