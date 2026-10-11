/// Provider-specific discovery requests, separate from typed search text.
enum DiscoveryCategory {
  trendingToday(
    'Trending Today',
    youtubeQuery: 'trending music today',
    time: 'week',
  ),
  topCharts(
    'Top Charts',
    youtubeQuery: 'top songs music charts',
    time: 'month',
  ),
  chill(
    'Chill / Lofi',
    youtubeQuery: 'chill lofi music',
    genre: 'Lo-Fi',
    time: 'week',
  ),
  workout('Workout', youtubeQuery: 'workout music', audiusQuery: 'workout'),
  pop('Pop', youtubeQuery: 'pop music', genre: 'Pop', time: 'week'),
  rock('Rock', youtubeQuery: 'rock music', genre: 'Rock', time: 'week');

  const DiscoveryCategory(
    this.label, {
    required this.youtubeQuery,
    this.audiusQuery = '',
    this.genre,
    this.time,
  });
  final String label;
  final String youtubeQuery;
  final String audiusQuery;
  final String? genre;
  final String? time;

  String get audiusDescription => switch (this) {
    trendingToday => 'Audius trending · past week',
    topCharts => 'Audius trending · past month',
    chill => 'Lo-Fi trending on Audius · past week',
    workout => 'Workout music search on Audius',
    pop => 'Pop trending on Audius · past week',
    rock => 'Rock trending on Audius · past week',
  };
}
