defmodule Sanbase.AI.ContentCandidatesTest do
  use Sanbase.DataCase

  import Sanbase.Factory

  alias Sanbase.AI.ContentCandidates
  alias Sanbase.Insight.Post
  alias Sanbase.Repo

  setup do
    user = insert(:user)
    described = insert(:post, user: user, ai_description: "AI text")
    pending = insert(:post, user: user)
    insert(:post, user: user, is_deleted: true)
    insert(:post)
    screener = insert(:screener, user: user)

    %{user: user, described: described, pending: pending, screener: screener}
  end

  test "list, count and pending_ids see only the user's non-deleted entities", context do
    %{user: user, described: described, pending: pending, screener: screener} = context

    {entities, 2} = ContentCandidates.list(:insights, user.id, 1, 10)
    assert Enum.sort(Enum.map(entities, & &1.id)) == Enum.sort([described.id, pending.id])
    assert {[_], 2} = ContentCandidates.list(:insights, user.id, 2, 1)
    assert ContentCandidates.pending_ids(:insights, user.id) == [{pending.id, :insights}]

    assert ContentCandidates.count(:watchlists, user.id) == 0
    assert ContentCandidates.pending_ids(:screeners, user.id) == [{screener.id, :screeners}]
  end

  test "override_descriptions copies the AI description", %{user: user} = context do
    assert {1, nil} = ContentCandidates.override_descriptions(:insights, user.id)
    assert Repo.get!(Post, context.described.id).short_desc == "AI text"
    assert Repo.get!(Post, context.pending.id).short_desc == nil
  end
end
