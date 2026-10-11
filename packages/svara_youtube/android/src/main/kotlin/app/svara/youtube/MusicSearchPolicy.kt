// SPDX-License-Identifier: GPL-3.0-or-later
package app.svara.youtube

/** Search heuristics, not an audio-content classifier. Never relax the noise filter for mixes. */
internal object MusicSearchPolicy {
    private val longMusic = Regex(
        """\b(mix|mixes|album|albums|compilation|concert|dj\s+set|extended\s+(mix|version))\b""",
        RegexOption.IGNORE_CASE
    )
    private val nonMusic = Regex(
        """\b(gameplay|walkthrough|playthrough|trailer|reaction|reacts|unboxing|review|interview|tutorial|vlog|podcast|news\s+live|live\s+news|full\s+episode|movie\s+clip|comedy\s+sketch|meme)\b|\bhow\s+to\s+(play|make|use|learn|install|fix|build|draw)\b""",
        RegexOption.IGNORE_CASE
    )

    fun allowsLongMusic(query: String): Boolean = longMusic.containsMatchIn(query)

    fun accepts(query: String, title: String, durationSeconds: Long): Boolean {
        if (nonMusic.containsMatchIn(title) || durationSeconds < 45) return false
        if (durationSeconds <= 20 * 60) return true
        // A long result also needs musical intent in its own title. Do not admit
        // a multi-hour stream merely because the search query contains "mix".
        return allowsLongMusic(query) && longMusic.containsMatchIn(title) &&
            durationSeconds <= 4 * 60 * 60
    }
}
