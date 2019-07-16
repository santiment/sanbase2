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
    from(ul in UserList,
      select: count(fragment("DISTINCT ?", ul.user_id))
    )
    |> Repo.one()
  end

  def users_with_watchlist_and_email() do
    from(ul in UserList,
      left_join: user in User,
      on: ul.user_id == user.id,
      where: not is_nil(user.email),
      select: {user, fragment("COUNT(?)", ul.id)},
      group_by: user.id
    )
    |> Repo.all()
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
