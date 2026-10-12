/// Bounded least-recently-used cache. Expiry is measured from insertion.
class MemoryCache<K, V> {
  MemoryCache({
    required this.capacity,
    required this.ttl,
    this.maxWeight,
    int Function(V)? weightOf,
    DateTime Function()? now,
  }) : _weightOf = weightOf ?? ((_) => 1),
       _now = now ?? DateTime.now;

  final int capacity;
  final Duration ttl;
  final int? maxWeight;
  final int Function(V) _weightOf;
  final DateTime Function() _now;
  final _entries = <K, ({V value, DateTime expires, int weight})>{};
  int _weight = 0;

  int get length {
    _prune();
    return _entries.length;
  }

  V? get(K key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (!entry.expires.isAfter(_now())) {
      _weight -= entry.weight;
      return null;
    }
    _entries[key] = entry;
    return entry.value;
  }

  void put(K key, V value) {
    remove(key);
    _prune();
    final weight = _weightOf(value);
    if (capacity <= 0 || (maxWeight != null && weight > maxWeight!)) return;
    while (_entries.isNotEmpty &&
        (_entries.length >= capacity ||
            (maxWeight != null && _weight + weight > maxWeight!))) {
      remove(_entries.keys.first);
    }
    _entries[key] = (value: value, expires: _now().add(ttl), weight: weight);
    _weight += weight;
  }

  void remove(K key) {
    final entry = _entries.remove(key);
    if (entry != null) _weight -= entry.weight;
  }

  void _prune() {
    final now = _now();
    for (final key in _entries.keys.toList()) {
      if (!_entries[key]!.expires.isAfter(now)) remove(key);
    }
  }
}
