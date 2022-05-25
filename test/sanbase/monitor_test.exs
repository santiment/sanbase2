defmodule Sanbase.MonitorTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.UserList
  alias Sanbase.UserList.Monitor
  alias Sanbase.Insight.Post
  alias Sanbase.Accounts.UserFollower

  setup do
    user = insert(:user)
    author = insert(:user, username: "tsetso")
    role_san_family = insert(:role_san_family)

    project = insert(:project, slug: "santiment")
    project2 = insert(:project, slug: "ethereum", ticker: "ETH", name: "Ethereum")

    [
      user: user,
      author: author,
      role_san_family: role_san_family,
      project: project,
      project2: project2,
      week_ago: Timex.shift(Timex.now(), days: -7)
    ]
  end

  describe "#watchlists_tags" do
    test "when watchlist has projects - returns tags", context do
      watchlist = create_watchlist(context) |> Sanbase.Repo.preload(list_items: [:project])

      assert Monitor.watchlists_tags([watchlist]) ==
               MapSet.new(
                 [
                   context.project.slug,
                   context.project.name,
                   context.project.ticker,
                   context.project2.slug,
                   context.project2.name,
                   context.project2.ticker
                 ]
                 |> Enum.map(&String.downcase/1)
               )
    end

    test "when watchlist has no projects - returns []", context do
      watchlist = create_watchlist(context, %{}, %{list_items: []})

      assert Monitor.watchlists_tags([watchlist]) == MapSet.new([])
    end
  end

  describe "#insights_to_send" do
    test "with insight from followed author returns it", context do
      UserFollower.follow(context.author.id, context.user.id)
      insight = create_insight(context)
      create_watchlist(context)
      Monitor.monitored_watchlists_for(context.user)

      insights_to_send =
        Monitor.insights_to_send(
          context.user,
          Monitor.monitored_watchlists_for(context.user),
          context.week_ago
        )
        |> Enum.map(& &1.id)

      assert insights_to_send == [insight.id]
    end

    test "with author in san clan returns it", context do
      insight = create_insight(context)

      insert(:user_role, user: context.author, role: context.role_san_family)
      create_watchlist(context)

      insights_to_send =
        Monitor.insights_to_send(
          context.user,
          Monitor.monitored_watchlists_for(context.user),
          context.week_ago
        )
        |> Enum.map(& &1.id)

      assert insights_to_send == [insight.id]
    end

    test "with not followed author, nor in san clan - returns []", context do
      create_insight(context)

      create_watchlist(context)

      insights_to_send =
        Monitor.insights_to_send(
          context.user,
          Monitor.monitored_watchlists_for(context.user),
          context.week_ago
        )
        |> Enum.map(& &1.id)

      assert insights_to_send == []
    end

    test "when insight is published more than one week ago - returns []", context do
      create_insight(context, %{
        published_at: Timex.shift(Timex.now(), days: -8) |> DateTime.to_naive()
      })

      create_watchlist(context)

      insights_to_send =
        Monitor.insights_to_send(
          context.user,
          Monitor.monitored_watchlists_for(context.user),
          context.week_ago
        )
        |> Enum.map(& &1.id)

      assert insights_to_send == []
    end

    test "when insight is with other tags - returns []", context do
      insert(:user_role, user: context.author, role: context.role_san_family)

      create_insight(context, %{
        tags: [build(:tag, name: "alabala")]
      })

      create_watchlist(context)

      insights_to_send =
        Monitor.insights_to_send(
          context.user,
          Monitor.monitored_watchlists_for(context.user),
          context.week_ago
        )
        |> Enum.map(& &1.id)

      assert insights_to_send == []
    end

    test "when the user is insight author - returns []", context do
      insert(:user_role, user: context.author, role: context.role_san_family)

      create_insight(context, %{user: context.user})

      create_watchlist(context)

      insights_to_send =
        Monitor.insights_to_send(
          context.user,
          Monitor.monitored_watchlists_for(context.user),
          context.week_ago
        )
        |> Enum.map(& &1.id)

      assert insights_to_send == []
    end

    test "when insight is with tag the name of the project - it returns it", context do
      insert(:user_role, user: context.author, role: context.role_san_family)

      insight =
        create_insight(context, %{
          tags: [build(:tag, name: "Ethereum")]
        })

      create_watchlist(context)

      insights_to_send =
        Monitor.insights_to_send(
          context.user,
          Monitor.monitored_watchlists_for(context.user),
          context.week_ago
        )
        |> Enum.map(& &1.id)

      assert insights_to_send == [insight.id]
    end

    test "when watchlist is not monitored - returns []", context do
      UserFollower.follow(context.author.id, context.user.id)
      create_insight(context)
      create_watchlist(context, %{is_monitored: false})

      insights_to_send =
        Monitor.insights_to_send(
          context.user,
          Monitor.monitored_watchlists_for(context.user),
          context.week_ago
        )
        |> Enum.map(& &1.id)

      assert insights_to_send == []
    end
  end

  defp create_insight(context, opts \\ %{}) do
    params =
      %{
        state: Post.approved_state(),
        ready_state: Post.published(),
        title: "Test insight",
        user: context.author,
        tags: [build(:tag, name: "BTC"), build(:tag, name: "santiment")],
        published_at: DateTime.to_naive(Timex.now())
      }
      |> Map.merge(opts)

    insert(:post, params)
  end

  def create_watchlist(context, create_opts \\ %{}, update_opts \\ %{}) do
    create_opts = %{user: context.user, is_monitored: true} |> Map.merge(create_opts)
    watchlist = insert(:watchlist, create_opts)

    update_opts =
      %{
        name: "My watch list of assets",
        id: watchlist.id,
        list_items: [%{project_id: context.project.id}, %{project_id: context.project2.id}]
      }
      |> Map.merge(update_opts)

    {:ok, watchlist} = UserList.update_user_list(context.user, update_opts)
    watchlist
  end
end
