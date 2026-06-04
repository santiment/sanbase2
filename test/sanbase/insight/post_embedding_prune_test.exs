defmodule Sanbase.Insight.PostEmbeddingPruneTest do
  use Sanbase.DataCase, async: true

  alias Sanbase.Insight.PostEmbedding

  # Executes the real `NOT IN (subquery)` DELETE against Postgres; an invalid
  # query would raise here rather than return a count.
  test "prune_all_stale/0 runs against the DB and returns a deleted count" do
    assert PostEmbedding.prune_all_stale() == 0
  end
end
