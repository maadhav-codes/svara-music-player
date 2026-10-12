/// A market is a chart population, never a recording-language filter.
class DiscoveryFilters {
  const DiscoveryFilters({this.market = 'global', this.scope = 'week'});
  final String market, scope;
}
