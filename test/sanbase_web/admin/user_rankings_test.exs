defmodule SanbaseWeb.Admin.UserRankingsTest do
  use Sanbase.DataCase

  import Sanbase.Factory

  alias SanbaseWeb.Admin.UserRankings

  test "ranks non-team creators by chart depth and excludes @santiment.net" do
    team = insert(:user, email: "dev@santiment.net")
    insert(:chart_configuration, user: team, metrics: Enum.map(1..50, &"m_#{&1}"))

    shallow = insert(:user, email: "shallow@example.com")
    insert(:chart_configuration, user: shallow, metrics: Enum.map(1..10, &"m_#{&1}"))

    deep = insert(:user, email: "deep@example.com")
    insert(:chart_configuration, user: deep, metrics: Enum.map(1..900, &"m_#{&1}"))
    insert(:chart_configuration, user: deep, metrics: ["x"])

    assert {:ok, %{rows: rows, rank_by: :max_chart_metrics}} =
             UserRankings.get(rank_by: :max_chart_metrics, limit: 100)

    ids = Enum.map(rows, & &1.user_id)
    refute team.id in ids
    assert shallow.id in ids
    assert deep.id in ids

    # deepest chart ranks first
    assert hd(rows).user_id == deep.id
    assert hd(rows).max_chart_metrics == 900
    assert hd(rows).charts == 2
  end

  test "rank_by: :charts orders by number of charts" do
    many = insert(:user, email: "many@example.com")
    for _ <- 1..3, do: insert(:chart_configuration, user: many, metrics: ["a"])

    few = insert(:user, email: "few@example.com")
    insert(:chart_configuration, user: few, metrics: ["a"])

    assert {:ok, %{rows: rows}} = UserRankings.get(rank_by: :charts, limit: 100)

    pos = fn id -> Enum.find_index(rows, &(&1.user_id == id)) end
    assert pos.(many.id) < pos.(few.id)
  end

  test "invalid rank_by falls back to :total_creations (no SQL injection)" do
    user = insert(:user, email: "safe@example.com")
    insert(:chart_configuration, user: user, metrics: ["a"])

    assert {:ok, %{rank_by: :total_creations, rows: rows}} =
             UserRankings.get(rank_by: "metrics; drop table users; --")

    assert Enum.any?(rows, &(&1.user_id == user.id))
  end

  test "attaches free_power_user flag to unpaid heavy creators" do
    user = insert(:user, email: "freepower@example.com")
    insert(:chart_configuration, user: user, metrics: Enum.map(1..600, &"m_#{&1}"))

    assert {:ok, %{rows: rows}} = UserRankings.get(rank_by: :max_chart_metrics, limit: 100)

    row = Enum.find(rows, &(&1.user_id == user.id))
    flag_keys = Enum.map(row.flags, &elem(&1, 0))
    assert :huge_chart in flag_keys
    assert :free_power_user in flag_keys
    refute row.is_paid
  end

  test "limit caps the number of returned rows" do
    for i <- 1..5 do
      user = insert(:user, email: "limit#{i}@example.com")
      insert(:chart_configuration, user: user, metrics: ["a"])
    end

    assert {:ok, %{rows: rows, limit: 2}} = UserRankings.get(rank_by: :charts, limit: 2)
    assert length(rows) == 2
  end
end
