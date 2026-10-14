# Recommendation feasibility and implementation guide

Analysis date: 14 October 2026. This guide is a proposal based on the current
repository; no application implementation or schema has been changed.

Yes, Svara can support useful personalized recommendations with its current
Flutter, Riverpod, SQLite, and YouTube architecture. A good first version does
not need a neural network or an account system. Matching Spotify's perceived
quality is a much larger goal: Svara lacks a population-wide listening dataset,
reliable recording metadata, and evidence that its recommendations improve
listener satisfaction. Quality must be measured rather than promised.

**1. What “like Spotify” should mean for this app**

Search and recommendation solve different problems. Search answers an explicit
query, so exact title/artist/version matches should remain prominent.
Recommendations infer what a listener might enjoy next. Personalizing search
must never hide the explicitly requested recording.

Spotify describes multiple recommendation systems for different surfaces,
including retrieval followed by ranking, with different goals for Discover
Weekly and Daily Mix. This supports a pipeline approach; it does not expose a
recipe for reproducing their quality. [Spotify's recommendation research](https://research.atspotify.com/2024/02/accelerating-creator-audience-building-through-centralized-exploration)

For Svara, define three separate products:

| Product | Goal | Earliest realistic version |
|---|---|---|
| Your mix | Familiar music plus a few discoveries | Local preference ranking over cached/library candidates |
| Because you liked… | Related recordings/artists | Seed retrieval; stronger with an external similarity source |
| Song radio / autoplay | Continue a listening session | Bounded queue extension using current song and session preferences |

Regional charts are a candidate source and a cold-start fallback, not evidence
of individual taste. A chart market does not establish recording language.

**2. Current implementation audit**

Paths below are relative to the repository root.

| Existing component | What it actually provides | Limitation for recommendations |
|---|---|---|
| `lib/core/store.dart`, `played()` / `history()` | Latest play timestamp per track, capped at 1,000 IDs | No play counts, listening duration, completions, skips, or metadata snapshot |
| `lib/features/player/svara_handler.dart` | Player lifecycle, completion, seek, queue navigation | Calls `played()` whenever playing becomes true, including resumes; this is not a qualified listen |
| `lib/core/providers.dart` and playlist repository | Favorite Track objects and playlists | Strong explicit signals, but no explicit dislikes |
| `lib/features/discovery/artist_favorites.dart` | Persisted followed artist identities | Useful seeds; follows alone miss changes in taste |
| `lib/features/discovery/personalized_feed.dart` | “From your artists”: searches followed artists, takes five tracks and three albums/radios each | Follow-based aggregation; no taste ranking or adjacent-artist discovery; three requests per followed artist |
| `lib/core/track.dart`, `quickMix()` | Interleaves local favorites and other tracks, favors less recently played tracks | Local-only heuristic; not collaborative filtering |
| `regional_youtube_catalog.dart` | Regional Top 100 snapshots | Popularity rather than personal relevance; IDs may refer to music videos |
| `ranked_discovery.dart`, `RankedMatcher` | Conservative recording matching using artist/title/version/duration | Useful adapter, but external candidates lacking duration cannot currently match |
| `youtube_repository.dart` and native `StudioAudioPolicy` | Songs-catalog search and evidence-based audio-only resolution | Retrieval/verification, not personalized ranking or waveform classification |
| `lib/core/memory_cache.dart` | Bounded cache with expiry | Reusable for candidate pools and profiles |

`DISCOVERY_CATALOG_URL` configures a discovery catalog, not a recommendation
service. The repository has a ListenBrainz chart adapter, but that is not a
connected personalized ListenBrainz integration. There is no recommendation
method in the native bridge today.

Online history contains only provider IDs; once tracks leave saved queues,
favorites, or playlists, the metadata needed to build a taste profile may be
unavailable. Store a minimal canonical recording snapshot with future signals.

**3. Recommended architecture**

```text
Playback / favorites / follows / explicit feedback
                    ↓
          Local listening-event repository
                    ↓
              Taste-profile builder
                    ↓
     Candidate sources → identity normalization
                    ↓
     Eligibility filters → preference ranking
                    ↓
       Diversity and repetition constraints
                    ↓
       Stable recommendation page / queue
                    ↓
        Existing studio-audio playback gate
```

Use a domain service independent of widgets, SQLite, and the native channel.
Inject adapters so provider changes do not change ranking rules.

```dart
// Proposed interfaces; not existing application APIs.
abstract interface class CandidateSource {
  Future<List<RecommendationCandidate>> retrieve(
    RecommendationContext context,
    CancelToken cancel,
  );
}

abstract interface class RecommendationService {
  Future<RecommendationPage> recommend(
    RecommendationRequest request,
    CancelToken cancel,
  );
}
```

Suggested new directory: `lib/features/recommendations/`. Keep event recording,
profile building, candidate adapters, ranking, and Riverpod state in separate
files. Make the ranker a pure function for deterministic tests. Put no network
work or scoring in a row's `build()` method.

Candidates should carry recording identity, canonical artists, provider ID when
known, version, duration when known, source provenance, source relevance,
metadata confidence, and eligibility state. Preserve uploader attribution
separately from recording artists. Do not infer genre, mood, language, BPM, or
release date from chart country or uploader names. Missing values remain unknown.

**4. Capture useful listening signals before choosing a model**

Add a versioned SQLite migration, preserving the existing history table for its
current consumers. Proposed schema shape:

```sql
CREATE TABLE listening_events (
  event_id TEXT PRIMARY KEY,
  playback_instance_id TEXT NOT NULL,
  track_id TEXT NOT NULL,
  occurred_at INTEGER NOT NULL,
  event_type TEXT NOT NULL,
  audible_ms INTEGER NOT NULL DEFAULT 0,
  duration_ms INTEGER,
  origin TEXT NOT NULL,
  reason TEXT,
  recommendation_id TEXT,
  metadata_json TEXT
);
CREATE INDEX listening_events_time ON listening_events(occurred_at);
CREATE INDEX listening_events_track ON listening_events(track_id);
```

Examples: qualified listen, natural completion, explicit next/previous,
favorite change, playlist addition, explicit “not interested,” recommendation
impression, and recommendation selection. Follow changes feed artist affinity.
Give each playback instance one final summary; retries and resumes must not
create duplicate listens. Exclude repeated rendering from impression counts.

Accumulate audible elapsed time while the engine is ready and actually playing.
Exclude pause, buffering, loading, interruptions, and sleep. Seek position is
not listened duration; seeking near the end is not evidence of a full listen.
Use monotonic elapsed time and reset the sample anchor on seek/track change.

Starting hypotheses to evaluate, rather than established universal rules:

- A qualified listen after `min(30 seconds, 50% of duration)` of audible time.
- A strong positive for natural completion with substantial audible coverage.
- A weak negative for explicit next within 15 audible seconds, after playback
  actually began. A repeated pattern is stronger than a single skip.
- No dislike inference from extraction failure, network loss, incoming call,
  seek, pause, queue removal, or automatic advance.
- Cap repeat-derived affinity so one looping session cannot dominate taste.

For unknown duration, use elapsed-time evidence without fabricating completion
fractions. Record whether a song was selected manually, recommended, or autoplayed;
exposure from the algorithm must not be mistaken for independent user preference.

Retain a proposed 90 days or 10,000 raw events, whichever cap is reached first,
plus bounded daily aggregates. Choose final limits after measuring storage.
Keep this local by default. Existing “Clear listening history” must also clear
derived profiles, event aggregates, cached personal recommendations, and history
seeds; explicit favorites/follows should remain unless separately removed.

**5. Start with local ranking and existing candidate sources**

Select at most five strong seeds from favorites, followed artists, and qualified
recent listens. Balance durable taste against the current session. Do not query
every followed artist during every refresh.

For the first release, combine local library tracks, saved online recordings,
bounded Songs searches for selected artists, and a small chart sample. This can
improve familiar mixes, but cannot reliably discover similar unfamiliar artists
without a richer relationship source. Broad queries such as “songs like X” are
search heuristics, not a dependable similarity graph.

Build normalized artist and recording affinities with time decay. Distinguish
recent-session affinity from long-term affinity; instrumentals, sleep music, or
shared-device sessions should not permanently reshape every recommendation.
Offer “Exclude this session from taste” as a later product control.

An illustrative ranking formula, with features scaled to comparable ranges:

```text
score = 0.30 × artist_affinity
      + 0.25 × seed_similarity
      + 0.20 × session_fit
      + 0.15 × positive_listening_evidence
      + 0.10 × discovery_value
      − recent_repeat_penalty
      − explicit_negative_penalty
```

These weights are proposed defaults, not probabilities or tested optimal values.
When a source lacks similarity features, use a separately calibrated baseline;
do not assign made-up similarity or compare raw scores from unrelated providers.
Treat blocked artists/recordings as hard exclusions, not merely score penalties.

After ranking, apply diversity constraints: no adjacent tracks from the same
artist; initially at most two tracks per artist in a 20-song discovery page;
roughly 15–20% exploration when enough eligible candidates exist. Familiar mixes
should allow more known music than discovery shelves. Relax quotas predictably
when the pool is small rather than inventing unrelated filler.

Deduplicate by provider ID and, where evidence permits, recording identity.
Preserve intentionally distinct studio versions and remasters. An ISRC/MBID is
useful identity evidence, not a reason to collapse every version with the same
title. Every item should explain its selection using real features, such as
“From an artist you follow” or “Similar to a song you saved.”

**6. Add a similarity source for stronger discovery**

| Option | Contribution | Cost / limitation | Recommendation |
|---|---|---|---|
| Existing YouTube Songs search | Recording retrieval and familiar-artist candidates | No authenticated personal YouTube Music profile in the current bridge | Keep as playback/catalog adapter |
| Last.fm similarity | Seed-based related tracks and artists | API key, metadata matching, variable coverage, provider failure handling | Evaluate as the first optional discovery adapter |
| ListenBrainz | Collaborative recording recommendations for a user | Account/listening-history integration and MBID resolution; recommendations may not yet exist | Optional later integration |
| Own collaborative backend | Learn from consenting Svara users and aggregate interactions | Backend, identity catalog, enough representative data, experiments | Defer until a real user population exists |
| Spotify API | Restricted external functionality | Not a dependable new-app shortcut to Spotify's recommender | Do not make it the foundation |

Last.fm documents `track.getSimilar` as listening-data-based and supports
`artist.getSimilar`; these reads require an API key but not a user login. They
return metadata/similarity, not verified YouTube playback IDs. Example request
shape: `method=track.getSimilar&artist=...&track=...&limit=20&format=json` plus the
API key. [Track similarity](https://www.last.fm/api/show/track.getSimilar),
[artist similarity](https://www.last.fm/api/show/artist.getSimilar).

ListenBrainz documents a collaborative recommendation endpoint returning
recording MBIDs and scores. It is experimental and can return 204 when user
recommendations have not been generated. A proposed integration would require
consented account/history setup and canonical identity mapping, not merely
enabling the existing sitewide chart adapter.
[ListenBrainz recommendation API](https://listenbrainz.readthedocs.io/en/latest/users/api/recommendation.html).

Spotify restricted Recommendations, Related Artists, Audio Features, and Audio
Analysis for new use cases in its November 2024 changes; existing extended-access
applications were treated differently. Plan around available adapters rather
than assuming that registering an app exposes Spotify's recommendations.
[Spotify API restrictions](https://developer.spotify.com/blog/2024-11-27-changes-to-the-web-api).

For optional external adapters, disclose that seed song/artist metadata is sent
to that provider; local ranking does not imply zero network disclosure. A backend
can protect service credentials and cache results; hiding keys with
`--dart-define` does not make credentials in an APK secret. Users' credentials
belong in suitable credential storage. Base local functionality must work when
an optional service is disabled or unavailable.

**7. Preserve studio-audio selection throughout recommendation delivery**

Recommendation metadata is not playback authorization. Similar-track APIs and
chart entries may lead to a cover, remaster, live performance, or cinematic upload.
Retrieve candidate recordings through Songs, match title/artist/version/duration
conservatively, and retain the existing native recording evidence and audio-only
MIME checks at playback time.

Reuse `RankedMatcher` principles, but avoid its chart-specific direct-playback
bypass for recommendation candidates. Its current duration requirement also
means incomplete external metadata needs enrichment or rejection, rather than
a confident match to the first search result. Keep per-candidate validation
states separate from taste scores. Favor already eligible Songs candidates;
validate a small display shortlist in the background if necessary. Do not
resolve hundreds of signed audio URLs to generate a feed.

On `no_studio_audio`, preserve the user's selection and report the unavailable
recording. For autoplay, exclude that failed candidate and choose another eligible
recommendation through a bounded fallback, without presenting it as the same song.
Recommendation quality cannot override recording identity or studio selection.

**8. Performance and queue integration**

Proposed starting budgets, to validate on an Android device:

- Rank at most 200 metadata candidates and present pages of 20.
- Reuse native limits: two active extractor workers and a bounded queue. Coordinate
  recommendations, charts, and artist feeds so their combined concurrency stays
  within these limits. Give user-initiated playback priority.
- Maintain one in-flight generation per surface with cancellation and generation
  checks. Network refreshes must not reorder an already visible page.
- Cache metadata candidate pools for a proposed six hours with a bounded capacity;
  taste changes invalidate ranking, not every source response. Keep provider tokens
  subject to their actual expiry. Never extend native recording-evidence expiry
  merely because a recommendation page remains cached.
- Show cached results promptly and refresh metadata in the background. Target
  local ranking p95 below 50 ms for 200 candidates; this is a target, not a benchmark.
- Use the existing virtualized list; append pages with stable recording keys.
  Snapshot candidate ordering and profile/model version for a recommendation cursor.

Add autoplay only after manual recommendation shelves work. Prefetch metadata
when roughly three queue tracks remain. Append results to the logical queue;
do not call `setQueue()` to replace the actively playing queue, because that
reloads playback. Add an explicit append operation with generation validation,
deduplication, queue-order updates, and persistence. Respect repeat-one/all,
sleep timers, explicit queue edits, and a user-visible autoplay toggle.
Network failure must leave existing playback uninterrupted.

**9. Delivery sequence and acceptance criteria**

| Phase | Deliverable | Exit criterion |
|---|---|---|
| A: Signals and identity | Local qualified listening events, metadata snapshots, profile reset | Seek/resume/buffering/call/retry cases produce correct, nonduplicated events |
| B: Local baseline | Cached “Your mix,” explicit negative feedback, diversity, explanations | Relevant mixes work offline; no blocked tracks or visible-page reshuffling |
| C: New discovery | Optional similarity adapter and conservative Songs mapping | Users discover useful unfamiliar artists; unverified mappings stay excluded |
| D: Autoplay | Stable queue append and bounded prefetch | No audio restart, duplicate queue entries, or ignored repeat/sleep controls |
| E: Population learning | Optional consented backend, collaborative candidates, learned ranker | Sufficient representative data and measured gains over the local baseline |

Do not require an LLM for phases A–D. Later models can improve candidate retrieval
or ranking if grounded in a real catalog, but cannot substitute for recording
identity, feedback collection, or availability checks.

Use today's followed-artist feed as a baseline and compare with local ranking,
then similarity-assisted ranking. Evaluate familiar mixes and discovery shelves
separately. Ask testers which of two blinded lists they prefer; your friend's
Spotify preference is a useful hypothesis, not a measured universal ranking.

Measure qualified listens per exposed recommendation, explicit dislikes,
early user skips, saves, new-artist saves, artist diversity, repeated exposure,
playback verification success, time-to-first-content, request count, and storage.
Define impression denominators and exclude network failures from taste metrics.
Small friend-group results are exploratory; do not claim statistical certainty.

For offline ranking experiments, split by time and build profiles using only
earlier events. Use actual exposure data when available; missing interaction is
not automatically dislike. Report recall/NDCG alongside coverage and playable
mapping rate so a relevant but unplayable list cannot look successful.

Keep evaluation local unless users explicitly opt into shared telemetry. Test
clear-history behavior and service-disabled fallbacks. This preserves the app's
current promise that personal listening history remains on the phone by default.

**Recommended next scope:** phases A and B, followed by a small Last.fm similarity
experiment. That fits the existing application and gives a measurable path to
better suggestions before taking on a recommendation backend or large model.
