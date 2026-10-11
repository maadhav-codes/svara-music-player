class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration time;
  final String text;
}

class Lyrics {
  const Lyrics({
    this.lines = const [],
    this.plain = '',
    this.instrumental = false,
    required this.source,
  });
  final List<LyricLine> lines;
  final String plain;
  final bool instrumental;
  final String source;
  bool get empty => lines.isEmpty && plain.trim().isEmpty && !instrumental;
  int activeIndex(Duration position) {
    var low = 0, high = lines.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (lines[mid].time <= position) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low - 1;
  }

  factory Lyrics.parse(
    String text, {
    required String source,
    String plain = '',
    bool instrumental = false,
  }) {
    final stamp = RegExp(r'\[(\d+):(\d{2})(?:[.:](\d{1,3}))?\]');
    final offsetMatch = RegExp(
      r'\[offset:\s*([+-]?\d+)\]',
      caseSensitive: false,
    ).firstMatch(text);
    final offset = int.tryParse(offsetMatch?.group(1) ?? '') ?? 0;
    final entries = <({int order, LyricLine line})>[];
    final untimed = <String>[];
    for (final row in text.replaceAll('\uFEFF', '').split('\n')) {
      final matches = stamp.allMatches(row).toList();
      if (matches.isEmpty) {
        if (row.trim().isNotEmpty && !row.trim().startsWith('[')) {
          untimed.add(row.trim());
        }
        continue;
      }
      final words = row.substring(matches.last.end).trim();
      for (final m in matches) {
        final seconds = int.parse(m[2]!);
        if (seconds >= 60) continue;
        final minutes = int.tryParse(m[1]!);
        if (minutes == null || minutes > 1440) {
          continue;
        }
        final ms =
            minutes * 60000 +
            seconds * 1000 +
            int.parse((m[3] ?? '').padRight(3, '0')) +
            offset;
        if (entries.length >= 2000) {
          continue;
        }
        entries.add((
          order: entries.length,
          line: LyricLine(Duration(milliseconds: ms < 0 ? 0 : ms), words),
        ));
      }
    }
    entries.sort((a, b) {
      final c = a.line.time.compareTo(b.line.time);
      return c == 0 ? a.order.compareTo(b.order) : c;
    });
    return Lyrics(
      lines: List.unmodifiable(entries.map((e) => e.line)),
      plain: plain.isNotEmpty ? plain : untimed.join('\n'),
      instrumental: instrumental,
      source: source,
    );
  }
}
