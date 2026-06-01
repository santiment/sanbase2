# Knowledge Indexing & FAQ Sync

How to (re)build the knowledge embedding indexes and how to copy production
FAQs into a local database for testing the knowledge bot.

All commands are run from `iex` (`iex -S mix`, or `iex` on a pod). There are
no mix tasks for these — the modules are the interface.

## Sources

The knowledge bot embeds three sources, referred to everywhere by the singular
atoms `:faq`, `:insight`, `:academy`:

| Source | Backing data | Owning module |
|---|---|---|
| `:faq` | `faq_entries` (admin-created) | `Sanbase.Knowledge.Faq` |
| `:insight` | published `posts` | `Sanbase.Insight.PostEmbedding` |
| `:academy` | markdown articles on GitHub | `Sanbase.Knowledge.Academy` |

## Re-indexing (re-embedding)

`Sanbase.Knowledge.Indexer` is the single entry point. It runs each source's
job sequentially (to avoid hammering the embedding API), isolates failures so
one source erroring does not abort the others, and returns
`%{source => %{status:, took_ms:, error:}}`.

```elixir
# Everything: FAQ + Insight + Academy
Sanbase.Knowledge.Indexer.reindex_all()

# A subset
Sanbase.Knowledge.Indexer.reindex([:faq, :insight])

# One source
Sanbase.Knowledge.Indexer.reindex(:faq)

# Academy accepts options (forwarded to Academy.reindex_academy/1)
Sanbase.Knowledge.Indexer.reindex(:academy, branch: "production", force: true)
Sanbase.Knowledge.Indexer.reindex(:academy, dry_run: true)
```

Notes:

- Requires `OPENAI_API_KEY` (embeddings) and a reachable Postgres.
- Cost/time: `:insight` re-embeds all published posts (thousands) and
  `:academy` fetches from GitHub — both are long. `:faq` is small.
- Adding a new source later is one `@sources` entry + one `do_reindex/2`
  clause in `Sanbase.Knowledge.Indexer`.

## Copying production FAQs to local

This is mostly used to **sync prod FAQs into a local dev database** for testing
the knowledge bot. FAQs are only created through the admin UI; there is no FAQ
API, so the only way to get real FAQs locally is to copy them via a JSON file
using `Sanbase.Knowledge.FaqSync`.

Embeddings are **not** copied — only `question` / `answer_markdown` /
`source_url` / `tags` and the original `id` travel. Re-embed locally after
import.

### 1. Export from prod (point your local app at the prod DB)

Run everything from your local machine — no pod needed. The export file lands
straight on your disk.

1. In `.env.dev`, uncomment the production `DATABASE_URL` line (it's there,
   commented out, next to the stage one).
2. (Re)start `iex -S mix` so it picks up the prod connection, then export:

   ```elixir
   Sanbase.Knowledge.FaqSync.export_to_file("./faqs.json")
   # => {:ok, %{path: "./faqs.json", count: 142}}
   ```

### 2. Import locally (switch back to the local DB first)

1. Comment the production `DATABASE_URL` back out in `.env.dev` so you're on
   the local DB again.
2. Restart `iex -S mix`, then import:

   ```elixir
   Sanbase.Knowledge.FaqSync.import_from_file("./faqs.json")
   # => {:ok, %{total: 142, inserted: 142, updated: 0, failed: 0}}
   ```

- **Idempotent**: entries are matched by their original `id`, so re-importing
  the same file updates in place instead of duplicating.
- **Production guard**: `import_from_file/1` refuses to run when the target
  looks like production — when `env == :prod` or `Sanbase.Utils.prod_db?/0`
  is true (the same `DATABASE_URL` / hostname check that `mix database_safety`
  uses). This is the safety net if you forget to comment `DATABASE_URL` back
  out: the import will refuse rather than write to prod.

### Alternative: export on a production pod

If you'd rather not point your local app at prod, export from an `iex` session
on a prod pod and copy the file over:

```elixir
Sanbase.Knowledge.FaqSync.export_to_file("/tmp/faqs.json")
```

Then copy the file to your machine (e.g. `kubectl cp <pod>:/tmp/faqs.json ./faqs.json`),
and import it locally as in step 2.

### 3. Re-embed locally

Imported FAQs have no embeddings yet, so they won't be retrieved until you
generate them:

```elixir
Sanbase.Knowledge.Indexer.reindex(:faq)
```

## Related

- `docs/knowledge-eval.md` — measuring retrieval quality (hit@K, MRR, context
  recall) with `mix knowledge_eval`.
