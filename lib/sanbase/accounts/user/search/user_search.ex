defmodule Sanbase.Accounts.Search do
  import Ecto.Query

  alias Sanbase.Accounts.User

  @max_size 50
  @default_size 20
  @min_pattern_length 3
  # Upper bound of rows fetched from the DB before ranking by similarity
  @max_candidates 200

  def max_size(), do: @max_size
  def min_pattern_length(), do: @min_pattern_length

  @doc """
  Search users by (part of) the username. The result is bounded: the pattern must
  be at least #{@min_pattern_length} characters (LIKE wildcards are matched
  literally), at most #{@max_size} users are returned and the DB never returns
  more than #{@max_candidates} candidate rows.
  """
  def by_username(username, size) when is_binary(username) do
    username = String.trim(username, "%")
    size = normalize_size(size)

    case String.length(username) >= @min_pattern_length do
      true -> do_by_username(username, size)
      false -> []
    end
  end

  def by_username(_username, _size), do: []

  defp do_by_username(username, size) do
    username_pattern = "%#{escape_like(username)}%"

    from(u in User,
      where: ilike(u.username, ^username_pattern),
      order_by: [asc: fragment("length(?)", u.username), asc: u.id],
      limit: @max_candidates,
      select: %{
        id: u.id,
        username: u.username,
        name: u.name,
        avatar_url: u.avatar_url
      }
    )
    |> Sanbase.Repo.all()
    |> Enum.sort_by(fn u -> String.jaro_distance(u.username, username) end, :desc)
    |> Enum.take(size)
  end

  defp normalize_size(size) when is_integer(size) and size > 0, do: min(size, @max_size)
  defp normalize_size(_), do: @default_size

  defp escape_like(string), do: String.replace(string, ~r/([\\%_])/, "\\\\\\1")

  def user_ids_with_santiment_email() do
    result =
      from(u in User,
        where: not is_nil(u.email) and ilike(u.email, "%@santiment.net"),
        select: u.id
      )
      |> Sanbase.Repo.all()

    {:ok, result}
  end
end
