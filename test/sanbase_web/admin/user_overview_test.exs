defmodule SanbaseWeb.Admin.UserOverviewTest do
  use Sanbase.DataCase

  import Sanbase.Factory

  alias SanbaseWeb.Admin.UserOverview
  alias Sanbase.UserList.ListItem
  alias Sanbase.Repo

  describe "lookup/1" do
    test "resolves by id, email and username" do
      user = insert(:user, email: "lookup@example.com", username: "lookupuser")

      assert {:ok, id} = UserOverview.lookup(to_string(user.id))
      assert id == user.id
      assert {:ok, ^id} = UserOverview.lookup("lookup@example.com")
      assert {:ok, ^id} = UserOverview.lookup("lookupuser")
    end

    test "returns error for unknown term or blank input" do
      assert {:error, _} = UserOverview.lookup("nobody@nowhere.test")
      assert {:error, _} = UserOverview.lookup("   ")
    end
  end

  describe "get/1" do
    test "counts creations and measures depth (metrics, assets)" do
      user = insert(:user, email: "abuser@example.com")

      insert(:chart_configuration, user: user, metrics: Enum.map(1..600, &"m_#{&1}"))
      insert(:chart_configuration, user: user, metrics: ["price_usd"])
      insert(:post, user: user)

      wl = insert(:watchlist, user: user)
      Repo.insert!(%ListItem{user_list_id: wl.id, project_id: insert(:random_project).id})
      Repo.insert!(%ListItem{user_list_id: wl.id, project_id: insert(:random_project).id})

      insert(:screener, user: user)

      assert {:ok, overview} = UserOverview.get(user.id)

      assert overview.creations.charts.count == 2
      assert overview.creations.insights.count == 1
      assert overview.creations.watchlists.count == 1
      assert overview.creations.screeners.count == 1

      assert overview.totals.max_chart_metrics == 600
      assert overview.totals.max_watchlist_assets == 2

      # charts list is ordered by metric depth, deepest first
      assert [deepest | _] = overview.creations.charts.list
      assert deepest.metrics == 600

      assert [wl_row] = overview.creations.watchlists.list
      assert wl_row.assets == 2
    end

    test "flags a free user with a huge chart as free_power_user" do
      user = insert(:user, email: "free@example.com")
      insert(:chart_configuration, user: user, metrics: Enum.map(1..600, &"m_#{&1}"))

      assert {:ok, overview} = UserOverview.get(user.id)

      refute overview.subscription.is_paid
      flag_keys = Enum.map(overview.flags, &elem(&1, 0))
      assert :huge_chart in flag_keys
      assert :free_power_user in flag_keys
    end

    test "a paid user with a huge chart is flagged huge_chart but not free_power_user" do
      user = insert(:user, email: "paid@example.com")
      insert(:subscription_pro_sanbase, user: user)
      insert(:chart_configuration, user: user, metrics: Enum.map(1..600, &"m_#{&1}"))

      assert {:ok, overview} = UserOverview.get(user.id)

      assert overview.subscription.is_paid
      flag_keys = Enum.map(overview.flags, &elem(&1, 0))
      assert :huge_chart in flag_keys
      refute :free_power_user in flag_keys
    end

    test "marks @santiment.net users as team" do
      user = insert(:user, email: "dev@santiment.net")

      assert {:ok, overview} = UserOverview.get(user.id)
      assert overview.user.is_team
    end

    test "errors for a missing user id" do
      assert {:error, _} = UserOverview.get(-1)
    end
  end
end
