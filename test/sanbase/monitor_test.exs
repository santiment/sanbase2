defmodule Sanbase.MonitorTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.UserList
  alias Sanbase.UserList.Monitor
  alias Sanbase.Insight.Post
  alias Sanbase.Following.UserFollower

  setup do
    user = insert(:user)
    author = insert(:user)
    role_san_clan = insert(:role_san_clan)

    project = insert(:project, slug: "santiment")
    project2 = insert(:project, slug: "ethereum", ticker: "ETH", name: "Ethereum")

    [
      user: user,
      author: author,
      role_san_clan: role_san_clan,
      project: project,
      project2: project2
    ]
  end

  test "#insights_to_send with followed author", context do
    UserFollower.follow(context.author.id, context.user.id)
    insight = create_insight(context)
    create_monitored_watchlist(context)

    insights_to_send = Monitor.insights_to_send(context.user) |> Enum.map(& &1.id)
    assert insights_to_send == [insight.id]
  end

  test "#insights_to_send with author in san clan", context do
    insight = create_insight(context)

    insert(:user_role, user: context.author, role: context.role_san_clan)
    create_monitored_watchlist(context)

    insights_to_send = Monitor.insights_to_send(context.user) |> Enum.map(& &1.id)
    assert insights_to_send == [insight.id]
  end

  defp create_insight(context) do
    insert(
      :post,
      state: Post.approved_state(),
      ready_state: Post.published(),
      user: context.author,
      tags: [build(:tag, name: "BTC"), build(:tag, name: "santiment")],
      published_at: DateTime.to_naive(Timex.now())
    )
  end

  def create_monitored_watchlist(context) do
    watchlist = insert(:watchlist, user: context.user, is_monitored: true)

    UserList.update_user_list(%{
      id: watchlist.id,
      list_items: [%{project_id: context.project.id}, %{project_id: context.project2.id}]
    })
  end
end
