defmodule Sanbase.UserList.Monitor do
  @moduledoc """
    Watchlist can be monitored - which means the creator will receive an email if any
  of the assets in the watchlist is present in the insights' tags created by SanClan
  or by followed authors.
  """

  import Ecto.Query

  alias Sanbase.UserList
  alias Sanbase.Auth.User
  alias Sanbase.Auth.User.{UserRole, Role}
  alias Sanbase.Insight.Post
  alias Sanbase.Repo

  def insights_to_send(user) do
    watchlists = monitored_watchlists_for(user)

    week_ago()
    |> insights_after_datetime()
    |> insights_by_followed_users_or_sanclan(user.id)
    |> insights_with_asset_in_monitored_watchlist(watchlists)
  end

  def watchlists_tags(watchlists) do
    watchlists
    |> Enum.flat_map(fn watchlist ->
      watchlist.list_items
      |> Enum.flat_map(&[&1.project.slug, &1.project.ticker, &1.project.name])
    end)
    |> Enum.dedup()
  end

  defp monitored_watchlists_for(%User{id: user_id}) do
    from(ul in UserList,
      where: ul.user_id == ^user_id and ul.is_monitored == true,
      preload: [list_items: [:project]]
    )
    |> Repo.all()
  end

  defp insights_after_datetime(datetime) do
    Post.public_insights_after(datetime)
  end

  defp insights_by_followed_users_or_sanclan(insights, user_id) do
    followed_users = Sanbase.Following.UserFollower.followed_by(user_id)
    san_clan_ids = san_clan_ids()

    insights
    |> Enum.filter(fn %Post{user_id: author_id} ->
      author_id != user_id and
        (author_id in san_clan_ids or author_id in followed_users)
    end)
  end

  defp insights_with_asset_in_monitored_watchlist(insights, watchlists) do
    watchlists_tags = watchlists_tags(watchlists)

    insights
    |> Enum.filter(fn %Post{tags: tags} ->
      tags
      |> Enum.any?(fn tag ->
        tag.name in watchlists_tags
      end)
    end)
  end

  defp users_with_email() do
    from(u in User, where: not is_nil(u.email))
    |> Repo.all()
  end

  defp week_ago(), do: Timex.shift(Timex.now(), days: -7)

  defp san_clan_ids() do
    from(ur in UserRole,
      where: ur.role_id == ^Role.san_clan_role_id(),
      select: ur.user_id
    )
    |> Repo.all()
  end
end
