defmodule Sanbase.UserLists.Statistics do
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.UserList

  def watchlists_created(%DateTime{} = from, %DateTime{} = to) do
    watchlists_query(from, to)
    |> select(fragment("count(*)"))
    |> Repo.one()
  end

  defp watchlists_query(from, to) do
    from_naive = DateTime.to_naive(from)
    to_naive = DateTime.to_naive(to)

    from(
      ul in UserList,
      where: ul.inserted_at >= ^from_naive and ul.inserted_at <= ^to_naive
    )
  end
end
