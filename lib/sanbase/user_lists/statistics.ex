defmodule Sanbase.UserLists.Statistics do
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.UserList
  alias Sanbase.Auth.User

  def watchlists_created(%DateTime{} = from, %DateTime{} = to) do
    watchlists_query(from, to)
    |> select(fragment("count(*)"))
    |> Repo.one()
  end

  def users_with_watchlist_count() do
    from(
      ul in UserList,
      select: count(fragment("DISTINCT ?", ul.user_id))
    )
    |> Repo.one()
  end

  def users_with_watchlist_and_email() do
    from(
      ul in UserList,
      left_join: user in User,
      on: ul.user_id == user.id,
      where: not is_nil(user.email),
      select: {user, fragment("COUNT(?)", ul.id)},
      group_by: user.id
    )
    |> Repo.all()
  end

  def new_users_with_watchlist_count(from_datetime) do
    from(
      ul in UserList,
      inner_join: user in User,
      on: ul.user_id == user.id,
      where: user.inserted_at > ^from_datetime,
      select: count(fragment("DISTINCT ?", ul.user_id))
    )
    |> Repo.one()
  end

  def old_users_with_new_watchlist_count(registered_datetime, watchlist_datetime) do
    from(
      ul in UserList,
      inner_join: user in User,
      on: ul.user_id == user.id,
      where:
        user.inserted_at < ^registered_datetime and
          ul.inserted_at > ^watchlist_datetime,
      select: count(fragment("DISTINCT ?", ul.user_id))
    )
    |> Repo.one()
  end

  # Private functions

  defp watchlists_query(from, to) do
    from_naive = DateTime.to_naive(from)
    to_naive = DateTime.to_naive(to)

    from(
      ul in UserList,
      where: ul.inserted_at >= ^from_naive and ul.inserted_at <= ^to_naive
    )
  end
end
