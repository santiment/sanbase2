defmodule Sanbase.Accounts.Search do
  import Ecto.Query

  alias Sanbase.Accounts.User

  def by_username(username) do
    username_pattern =
      case String.starts_with?(username, "%") or String.ends_with?(username, "%") do
        true -> username
        false -> "%#{username}%"
      end

    from(u in User,
      where: ilike(u.username, ^username_pattern),
      select: %{
        id: u.id,
        username: u.username,
        name: u.name,
        avatar_url: u.avatar_url
      }
    )
    |> Sanbase.Repo.all()
    |> Enum.sort_by(fn u -> String.jaro_distance(u.username, username) end, :desc)
  end
end
