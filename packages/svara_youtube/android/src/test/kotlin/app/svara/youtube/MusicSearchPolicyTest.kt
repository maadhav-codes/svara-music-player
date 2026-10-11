package app.svara.youtube

import org.junit.Assert.*
import org.junit.Test

class MusicSearchPolicyTest {
    @Test fun durationBoundariesAndUnknownDurations() {
        for (duration in listOf(-1L, 0L, 44L, 1201L, 14400L)) {
            assertFalse("duration $duration", MusicSearchPolicy.accepts("Batman music", "Batman theme", duration))
        }
        for (duration in listOf(45L, 180L, 1200L)) {
            assertTrue(MusicSearchPolicy.accepts("Batman music", "Batman theme", duration))
        }
    }

    @Test fun excludesNoiseRegardlessOfDurationOrMixIntent() {
        for (title in listOf("Batman GAMEPLAY", "Trailer reaction", "Music production tutorial", "Artist interview", "New album review", "How to play guitar", "Vlog", "Podcast episode 10", "Meme compilation", "Live news", "Full episode", "Movie clip", "Comedy sketch")) {
            assertFalse(title, MusicSearchPolicy.accepts("music mix", title, 180))
        }
    }

    @Test fun preservesMusicalTitlesAndPerformances() {
        for (title in listOf("How to Save a Life", "Batman soundtrack", "Star Wars theme (official audio)", "Live performance", "News of the World", "Acoustic cover", "Remix", "Lyric video")) {
            assertTrue(title, MusicSearchPolicy.accepts("music", title, 180))
        }
    }

    @Test fun longMusicNeedsExplicitIntentAndMusicalTitle() {
        assertTrue(MusicSearchPolicy.accepts("lofi mix", "Lofi mix", 14400))
        assertTrue(MusicSearchPolicy.accepts("full album", "Full album", 3600))
        assertTrue(MusicSearchPolicy.accepts("DJ set", "DJ set", 7200))
        assertFalse(MusicSearchPolicy.accepts("Coldplay music", "Full album", 3600))
        assertFalse(MusicSearchPolicy.accepts("lofi mix", "Spoken livestream", 3600))
        assertFalse(MusicSearchPolicy.accepts("lofi mix", "Lofi mix", 14401))
        assertFalse(MusicSearchPolicy.accepts("full album", "Full album", 30))
        assertFalse(MusicSearchPolicy.allowsLongMusic("remix music"))
    }
}
