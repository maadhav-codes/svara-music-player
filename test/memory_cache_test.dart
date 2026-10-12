import 'package:flutter_test/flutter_test.dart';
import 'package:svara/core/memory_cache.dart';

void main() {
  test('reads promote entries and TTL expires without sliding on access', () {
    var now = DateTime(2026);
    final cache = MemoryCache<String, String>(
      capacity: 2,
      ttl: const Duration(minutes: 1),
      now: () => now,
    );
    cache.put('a', 'first');
    cache.put('b', 'second');
    expect(cache.get('a'), 'first');
    cache.put('c', 'third');
    expect(cache.get('b'), isNull);
    now = now.add(const Duration(seconds: 59));
    expect(cache.get('a'), 'first');
    now = now.add(const Duration(seconds: 1));
    expect(cache.get('a'), isNull);
    expect(cache.length, 0);
  });
  test('replacement, expiry and byte limits release capacity correctly', () {
    var now = DateTime(2026);
    final cache = MemoryCache<String, String>(
      capacity: 64,
      ttl: const Duration(minutes: 1),
      maxWeight: 5,
      weightOf: (s) => s.length,
      now: () => now,
    );
    cache.put('a', '123');
    cache.put('b', '12');
    cache.put('a', '1');
    cache.put('c', '12');
    expect(cache.length, 3);
    cache.put('large', '123456');
    expect(cache.get('large'), isNull);
    expect(cache.length, 3);
    now = now.add(const Duration(minutes: 1));
    cache.put('new', '12345');
    expect(cache.length, 1);
    expect(cache.get('new'), '12345');
  });
}
