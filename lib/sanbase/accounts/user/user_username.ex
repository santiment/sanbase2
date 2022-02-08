defmodule Sanbase.Accounts.User.Username do
  import Ecto.Query

  def valid?(nil), do: {:error, "Username must be a string and not null"}

  def valid?(username) when is_binary(username) do
    username = String.downcase(username) |> String.trim()

    with true <- valid_string?(username),
         true <- valid_length?(username),
         true <- is_not_taken?(username) do
      true
    end
  end

  defp valid_string?(username) do
    ascii_printable? =
      username
      |> String.to_charlist()
      |> List.ascii_printable?()

    case ascii_printable? do
      true -> true
      false -> {:error, "Username must contain only valid ASCII symbols"}
    end
  end

  defp valid_length?(username) do
    case String.length(username) do
      len when len <= 3 -> {:error, "Username must be at least 4 characters long"}
      _ -> true
    end
  end

  defp is_not_taken?(username) do
    query =
      from(u in Sanbase.Accounts.User,
        where: u.username == ^username,
        select: fragment("count(*)")
      )

    case Sanbase.Repo.one(query) do
      1 -> {:error, "Username is taken"}
      0 -> true
    end
  end
end
