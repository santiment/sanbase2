# Academy search — status and roadmap

Covers the `academySearch` and `academyAutocompleteQuestions` GraphQL queries and the
Academy index behind them (`Sanbase.Knowledge.Academy`), which also feeds the Academy Q&A
chat (`sendChatMessage` with `type: ACADEMY_QA`).

Last updated: 2026-09-29.

## How we measure

`Sanbase.Knowledge.AcademySearchEval` runs the exact production search function
(`AcademyAIService.semantic_search/2`) over the golden set in
`priv/knowledge/eval/academy_search_set.exs`: 32 questions (28 answerable, 4 the Academy
does not cover), each with expected pages and short answer phrases taken from the source.
It calls the function directly, so it works from a remote shell, needs no HTTP access and
is not rate limited.

```elixir
alias Sanbase.Knowledge.AcademySearchEval, as: E

r = E.run(runs: 3)                  # ~2-3 minutes
E.print(r)
E.save(r, "/tmp/academy_eval.json")
E.compare(E.load("/tmp/academy_eval_before.json"), r)
E.index_stats()                     # stored-chunk quality, no API calls
```

Main metrics:
- `hit_at_1`, `hit_at_5`, `mrr`: the expected page's rank.
- `relevant_at_1`, `relevant_at_3`: the same, but also counting acceptable pages.
- `fact_recall_top5`: the share of answer phrases found in the top 5 chunks.
- `distinct_pages_top5`.
- `stability_top5`: top-5 overlap across identical calls.
- `markup_chunks_top5`, `stub_chunks_top5`.
- `negative_max_similarity`.
- Latency p50/p95.

With 28 answerable questions, one question is about 3.5 points, so differences of one
question are noise. See "Grow the golden set" below.

## Done (branch `academy-search-quality`)

Local before/after, with a full reindex each time and 32 questions × 3 runs:

| | before | after |
|---|---|---|
| Right page at rank 1 | 78.6% | 78.6% |
| Relevant page at rank 1 / in top 3 | 24 / 27 of 28 | 24 / 27 |
| Answer phrases in top 5 | 0.929 | 0.917 |
| Distinct pages in top 5 | 3.84 | 4.16 |
| Same top 5 on repeated calls | 0.71 | 0.98 |
| Top-5 chunks with leftover markup | 3.06 | 0 |
| Index chunks / with markup / stubs / bad headings | 1407 / 497 / 162 / 10 | 1071 / 0 / 20 / 0 |
| Latency p50 / p95 | 992 / 1568 ms | 981 / 1368 ms |

- **Endpoint guard.**
  - `topK` must be 1..50. Blank queries and queries over 1000 characters are rejected.
  - Upstream errors are logged, not returned.
  - Per-caller rate limits with minute, hour and day windows (`PublicRateLimit`, see
    `config/config.exs`). Anonymous callers are keyed by IP, API key/JWT users by user id.
    The limits can be changed at runtime with `Application.put_env`.
- **Chunking** (`Sanbase.Knowledge.AcademyMarkdown`, index version 3).
  - Strips frontmatter, MDX imports, JSX, iframes/video and images. Code is untouched.
  - Section-based chunks, with small sections merged up to 800 characters.
  - Clean headings.
  - `Title > Breadcrumb` is prepended to the embedded text.
  - Fixed titles that came out as `#`.
  - A markup-only page no longer aborts the reindex.
- **Rerank.** `temperature: 0` (results were random before). The reranker sees the section
  heading. At most 2 chunks per page are returned.
- **Reindex safety.**
  - An advisory lock so two reindexes cannot commit at once.
  - `Academy.backup_index/1`, `restore_index/1` and `drop_index_backup/1`.

### Rollout (remote shell; mix is not available on stage/prod)

1. After the deploy, run `E.run(runs: 3)` and save it as the baseline. Retrieval changes
   are live, but the index is still v2.
2. `Sanbase.Knowledge.Academy.backup_index("pre_v3")`.
3. `Sanbase.Knowledge.Academy.reindex_academy(force: true)`. Run it manually, away from
   the daily 17:00 job. It needs a valid `GITHUB_ACADEMY_SCRAPER_TOKEN`; a full run makes
   about 355 GitHub API calls.
4. Run `E.run(runs: 3)` and `E.compare/2` against the baseline, plus `E.index_stats()`.
5. If it is worse, `Sanbase.Knowledge.Academy.restore_index("pre_v3")` swaps back in one
   transaction. After a few stable days, `drop_index_backup("pre_v3")`.

## Left to implement

Ordered by expected user impact.

### 1. "Not covered" signal
**Why:** For questions the Academy does not answer, search still returns confident-looking
results. For example, a refund question returns billing pages and a Google Trends question
returns Social Trends pages. The LLM consumers (the Academy Q&A chat, MCP, the Telegram bot)
then make up an answer.

Cosine similarity cannot separate these cases. Uncovered questions score up to 0.573, while
correct answers score as low as 0.409.

**What:**
- Use a reranker that returns a relevance score (next item).
- Calibrate a threshold on the golden set's negative items.
- Return nothing, or flag results as `low_confidence`, below it.

**Measure:** a new metric, the negatives' max rerank score vs the answerable items'
rank-1 score. Add more negative questions to the golden set.

### 2. Cohere reranker (scores + latency)
**Why:**
- The listwise `gpt-4o-mini` reranker returns only an order, with no scores.
- It is the largest latency cost.
- `Sanbase.Knowledge.Reranker.OpenRouterCohere` (`rerank-v3.5`) already exists: a
  cross-encoder that returns scores and is likely faster.

**What:**
- A/B it with `E.run(search_opts: [reranker: Sanbase.Knowledge.Reranker.OpenRouterCohere])`
  on the live index.
- Switch the default if it is not worse.
- Expose its score in the `academySearch` result. Today `similarity` is the pre-rerank
  cosine, which does not follow the returned order.

### 3. Autocomplete returns nothing for most prefixes — done (branch `academy-autocomplete`)
`academyAutocompleteQuestions` no longer calls aiserver. aiserver had 222 questions for 74 of
355 pages and matched the whole query as one substring.

- Each article stores about 5 questions (`academy_articles.suggested_questions`), written by
  `gpt-5.4-mini` from the indexed chunks. Generation is manual, never part of the reindex; the
  reindex keeps stored questions (see `Sanbase.Knowledge.AcademyQuestions`).
- Matching is in memory over the questions, article titles and section headings: every word
  must match, the last word may be partial, and close misspellings match. When nothing
  matches all words, all but one is enough. At most 2 questions per article. About 2ms per
  lookup, with no API call.
- The result also returns the article `url`.

Measured with `E.run_autocomplete()` over `priv/knowledge/eval/academy_autocomplete_set.exs`
(36 answerable prefixes, 4 not covered). The "before" is prod aiserver:

| | aiserver | sanbase |
|---|---|---|
| Prefixes with no suggestion | 58% | 0% |
| Expected page in suggestions (top 5) | 31% | 92% |
| Expected page first | 28% | 78% |
| Latency | ~140 ms (HTTP hop) | ~2 ms |

"Not covered" prefixes now get a suggestion half of the time, from the all-but-one-word
fallback (e.g. "google trends" suggests Sansheets in Google Sheets).

**Rollout:**
1. Deploy (runs the migration). Autocomplete returns `[]` until step 2.
2. Remote shell: `Sanbase.Knowledge.AcademyQuestions.generate()`. About 1 minute, 355 LLM
   calls. Other pods pick the questions up within 10 minutes.
3. `E.run_autocomplete() |> E.print_autocomplete()` and `AcademyQuestions.stats()`.
4. After new Academy content: `generate()` again (only articles without questions). After
   big edits: `generate(stale: true)`.

`/academy/autocomplete-questions` in aiserver can be removed after the rollout.

### 4. Rate limits and LLM cost across pods; rate-limit the Q&A chat
**Why:** Every search costs an embedding plus an LLM rerank, and every Q&A chat answer costs
an LLM completion. The current limits are node-local ETS counters: with N pods a caller gets
up to N times the limit, and a deploy resets the day window.

`sendChatMessage` (`ACADEMY_QA` and DYOR) has no per-caller limit at all, and it is the most
expensive call.

**What:**
- Add `PublicRateLimit` with minute, hour and day windows to `sendChatMessage` (anonymous
  callers per IP, users per id).
- For real daily budgets, move the counters to a shared store (Postgres or Redis), or reuse
  the `ApiCallLimit` machinery.
- Check real traffic in the prod logs (calls per minute per IP, p99) and set the limits
  just above it.

### 5. Sansheets function chunks: heading lands in the wrong chunk
**Why:** On the Sansheets function pages each function is a `## SAN_X` heading followed by a
`##### SAN_X(args)` body of about 700 characters. Merging sections up to 800 characters
sometimes puts function B's `## SAN_B` heading at the end of function A's chunk. B's chunk
then starts at the `#####` line, and its heading shows as `SAN_EXCHANGE_INFLOW(projectSlug,
from, t…` instead of `SAN_EXCHANGE_INFLOW`.

Ranking is fine: in the eval, the stub chunks no longer beat the metric pages. But the
headings shown to users and to the reranker are messy, and one chunk mixes two functions.

**What:** in `AcademyMarkdown.merge_small_sections/3`, stop merging when the next section
starts a heading at the same or a higher level than the chunk's first heading, once the
chunk has body text. Then reindex locally and re-run the eval.

### 6. Grow the golden set with real user questions
**Why:** 28 answerable questions can only show large changes. The questions were written by
us, not by users.

**What:**
- Sample 100–200 real questions from `question_answer_log`.
- Label the expected pages and answer phrases.
- Add more "not covered" questions.

### 7. Answer-level eval for the Academy Q&A chat
**Why:** The current eval measures retrieval only. What users see is the LLM answer: whether
it is correct, whether it cites the right page, and whether it refuses when the Academy does
not cover the question.

**What:** extend the eval to run `AcademyAIService.generate_local_response` without saving a
chat, then score the answer against the answer phrases and the cited URLs. Use an LLM judge
for correctness.

### 8. Caching
**Why:** Every call pays for an embedding and a rerank, and repeated or popular queries are
common.

**What:** a Cachex entry from normalized query to results, with a TTL of about 1h, cleared
after a reindex. This lowers cost and latency, and it also makes rate limits less critical.

### 9. Vector query cannot use the HNSW index
**Why:** `Academy.search_chunks` orders by `1 - (embedding <=> q) DESC`. pgvector uses the
HNSW index only for `ORDER BY embedding <=> q ASC`, so this is most likely a sequential scan.
It is fine at 1–1.5k chunks but grows linearly.

**What:** change the ORDER BY, set `hnsw.ef_search`, and confirm with `EXPLAIN`.

### 10. Embedding client on the request path
**Why:** The query embedding uses a 60s timeout and up to 12 retries
(`lib/openai/embeddings/openai.ex`). One slow OpenAI call can hold a request for a minute.

**What:** a request-path option with about a 5s timeout and at most 1 retry.

### 11. Indexer robustness
**Why:** One fetch or embedding error, or two files mapping to the same `academy_url`
(`{:ok, _} =` match), still aborts the whole daily reindex.

**What:** skip and log per-file failures, and handle `academy_url` collisions.

### 12. Academy content fixes (academy repo, not sanbase)
Found during the eval:
- `sansheets/functions/` is only a list of links, so the typo query "sansheet functons"
  ranks it below onboarding pages. Add a short intro sentence.
- The query-complexity example text says "3650 days, 1 hour", but its code uses 1500 days
  at 30 minutes.
- The Sansheets pages still say "Add-ons" and "stake of SAN tokens".
