defmodule Sanbase.UserList.Monitor do
  @moduledoc """
    Watchlist can be monitored - which means the creator will receive an email if any
  of the assets in the watchlist is present in the insights' tags created by SanClan
  or by followed authors.
  """

  import Ecto.Query

  alias Sanbase.UserList
  alias Sanbase.Auth.User
  alias Sanbase.Insight.Post
  alias Sanbase.Repo

  # insights from last week with tags and authors

  def monitored_watchlists_for(%User{id: user_id}) do
    from(ul in UserList,
      where: ul.user_id == ^user_id and ul.is_monitored == true,
      preload: [list_items: [:project]]
    )
    |> Repo.all()
  end

  def insights_after_datetime(datetime) do
    Post.public_insights_after(datetime)
  end

  defp week_ago(), do: Timex.shift(Timex.now(), days: -7)
end
