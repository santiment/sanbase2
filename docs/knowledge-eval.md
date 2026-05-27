# Knowledge Retrieval Eval

Offline harness for measuring `Sanbase.Knowledge` retrieval quality across
FAQ, Academy, and Insight sources. Run it before and after any change to
the embedding model, similarity threshold, chunking, prompt, or retrieval
logic. Diff the numbers to decide whether the change shipped a win or a
regression.

## What it measures

Per source (`faq` / `academy` / `insights`):

| Metric | Meaning |
|---|---|
| `hit@1` | fraction of questions whose first expected id is rank 1 |
| `hit@3` / `hit@5` / `hit@10` | same at rank ≤ K |
| `MRR` | mean of `1 / first_rank` (0 if not retrieved) |
| `mean top1 similarity` | average cosine similarity of the top hit |

Items with empty `expected.*_ids` are **skipped** for hit-rate scoring but
still contribute their top-1 similarity — useful for off-topic sentinels
(e.g. "weather tomorrow?") where you only care that nothing scores high.

## Pieces

| Path | Role |
|---|---|
| `lib/sanbase/knowledge/eval.ex` | scoring + orchestration (`run/1`, `score_hits/3`, `summarize/2`) |
| `lib/mix/tasks/knowledge_eval.ex` | `mix knowledge_eval` CLI |
| `priv/knowledge/eval/golden_set.exs` | golden Q-set with expected ids |
| `test/sanbase/knowledge/eval_test.exs` | unit tests for scoring math |

## Running it

Requires `OPENAI_API_KEY` (one embedding per golden question) and a
Postgres connection with FAQ / Academy / Insight embeddings populated.

```sh
# Full eval, all sources
mix knowledge_eval

# One source at a time
mix knowledge_eval --source faq
mix knowledge_eval --source faq,academy

# Baseline JSON dump for run-to-run diffing
mix knowledge_eval --source faq --json /tmp/eval-baseline.json

# Per-question rank breakdown
mix knowledge_eval --source faq --verbose

# Faster iteration loop
mix knowledge_eval --source faq --limit 10 --top-k 20

# Custom golden set (e.g. focused on one bug)
mix knowledge_eval --file priv/knowledge/eval/regression.exs
```

If `mix knowledge_eval` fails on `:eaddrinuse`, the dev server is bound to
port 4000 — stop it or run with `PORT=4001 mix knowledge_eval ...`.

## The golden set

`priv/knowledge/eval/golden_set.exs` returns:

```elixir
%{
  version: 1,
  items: [
    %{
      id: "faq-api-key-where",
      question: "Where do I get my Santiment API key?",
      expected: %{
        faq_ids: ["7a5e4e22-232e-45cf-8aa4-f9a58700d3e5"],
        academy_paths: [],
        insight_post_ids: []
      },
      tags: ["api", "onboarding"]
    },
    ...
  ]
}
```

### Authoring rules

1. **Questions are paraphrased, not verbatim.** Verbatim FAQ titles
   trivially retrieve themselves and measure embedding self-similarity,
   not real retrieval quality. Phrase each question the way a user would
   actually type it.
2. **`id` is a short, stable kebab-case slug.** It only labels the item
   in reports; it has nothing to do with the underlying FAQ uuid.
3. **`expected.faq_ids`** — FaqEntry binary_id (uuid string).
4. **`expected.academy_paths`** — `github_path` value from
   `AcademyArticle` (e.g. `"sanpy/README.md"`).
5. **`expected.insight_post_ids`** — `Post.id` integer.
6. **Empty `expected.*_ids`** is allowed and meaningful — skips hit
   scoring for that source but tracks mean top-1 similarity. Use for
   off-topic / should-not-answer sentinels.
7. **`tags`** are free-form labels for future per-tag slicing. Keep them
   short and reuse them across items where possible.

### Extending the FAQ set

The current set was generated on 2026-05-26 from
`Sanbase.Knowledge.Faq.list_entries/0`. When new FAQ entries land, dump
the current ids:

```sh
mix run -e '
  entries = Sanbase.Knowledge.Faq.list_entries()
  json = Enum.map(entries, fn e -> %{id: e.id, question: e.question} end)
         |> Jason.encode!(pretty: true)
  File.write!("/tmp/faq_entries.json", json)
'
```

Diff against the uuids already in `golden_set.exs` and add a paraphrased
item for each new entry.

### Filling Academy / Insight expected lists

Empty by default. To add coverage:

- **Academy** — find the `github_path` of the article that should answer
  a question (`Sanbase.Knowledge.Academy.list_articles/0`) and put it in
  `expected.academy_paths`.
- **Insights** — find the relevant `Post.id`. Put one or more in
  `expected.insight_post_ids`. The eval deduplicates Insight chunks by
  `post_id` before scoring, so a post counts as one hit regardless of how
  many of its chunks rank.

## Interpreting results

```text
[faq] evaluated=63
  hit@1   0.730
  hit@3   0.905
  hit@5   0.937
  hit@10  0.952
  MRR     0.812
  mean top1 sim 0.601
```

- `evaluated` is the number of golden items with non-empty `expected.faq_ids`.
- `hit@1` ≥ 0.7 and `hit@3` ≥ 0.85 are reasonable floors for an
  in-domain FAQ set. Below that, retrieval is leaving easy wins on the
  table.
- `mean top1 sim` is most useful **directionally** — compare across runs,
  don't compare absolute values across sources (FAQ chunks are denser
  than Academy chunks).
- If `hit@1` drops while `hit@10` stays flat, you have a **ranking**
  problem (rerank or threshold), not a recall problem.
- Watch the off-topic sentinels: if their `top1_similarity` rises into
  the same band as real hits, your no-info threshold is no longer
  protective.

## Workflow for retrieval changes

1. `mix knowledge_eval --source faq --json /tmp/before.json` on `master`.
2. Apply your change on a branch.
3. `mix knowledge_eval --source faq --json /tmp/after.json`.
4. Diff the `summary` sections of both JSON files. If `hit@K` or `MRR`
   regress, the change does not ship.

## Unit tests

`test/sanbase/knowledge/eval_test.exs` covers `score_hits/3` and
`summarize/2`. These run without DB or OpenAI access:

```sh
mix test test/sanbase/knowledge/eval_test.exs
```

Touch them whenever scoring semantics change (new metric, new edge
case).
