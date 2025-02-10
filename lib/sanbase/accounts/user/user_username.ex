defmodule Sanbase.Accounts.User.Name do
  @moduledoc false
  import Ecto.Query

  def valid_name?(nil), do: {:error, "Name must be a string and not null"}

  def valid_name?(name) do
    # The downcase is only to make the checks easier
    name = name |> String.downcase() |> String.trim()

    with true <- valid_utf8_string?(name, "Name"),
         true <- valid_length?(name, "Name"),
         false <- has_forbidden_characters?(name, "Name"),
         false <- forbidden?(name, "Name"),
         false <- swear?(name, "Name") do
      true
    end
  end

  def valid_username?(nil), do: {:error, "Username must be a string and not null"}

  def valid_username?(username) when is_binary(username) do
    username = username |> String.downcase() |> String.trim()

    with true <- valid_ascii_string?(username, "Username"),
         true <- valid_length?(username, "Username"),
         false <- has_forbidden_characters?(username, "Username"),
         false <- taken?(username, :username, "Username"),
         false <- forbidden?(username, "Username"),
         false <- swear?(username, "Username") do
      true
    end
  end

  defp valid_utf8_string?(value, fieldname) do
    if String.valid?(value) do
      true
    else
      {:error, "#{fieldname} must be a valid UTF-8 string"}
    end
  end

  defp valid_ascii_string?(value, fieldname) do
    ascii_printable? =
      value
      |> String.to_charlist()
      |> List.ascii_printable?()

    if ascii_printable? do
      true
    else
      {:error, "#{fieldname} must contain only valid ASCII symbols"}
    end
  end

  defp has_forbidden_characters?(value, fieldname) do
    if String.contains?(value, [">", "<", "/", "\\"]) do
      {:error, "#{fieldname} must not contain the forbidden characters >, <, /, \\"}
    else
      false
    end
  end

  defp valid_length?(value, fieldname) do
    case String.length(value) do
      len when len <= 3 -> {:error, "#{fieldname} must be at least 4 characters long"}
      _ -> true
    end
  end

  defp taken?(value, field, fieldname) do
    query =
      from(u in Sanbase.Accounts.User,
        where: fragment("lower(?)", field(u, ^field)) == ^value,
        select: fragment("count(*)")
      )

    case Sanbase.Repo.one(query) do
      0 -> false
      _ -> {:error, "#{fieldname} is taken"}
    end
  end

  @forbiden_names [
    "admin",
    "administrator",
    "superuser",
    "anonymous",
    "root",
    "moderator",
    "santiment",
    "santeam",
    "san-team",
    "santimentteam",
    "santiment-team",
    "<script>",
    "</script>",
    "<js>",
    "</js>"
  ]
  defp forbidden?(value, fieldname) do
    if value in @forbiden_names or
         Enum.any?(@forbiden_names, fn u ->
           String.starts_with?(value, u) or String.ends_with?(value, u)
         end) do
      {:error, "#{fieldname} is not allowed. Choose another #{String.downcase(fieldname)}"}
    else
      false
    end
  end

  @config Expletive.configure(blacklist: Expletive.Blacklist.english())
  defp swear?(value, fieldname) do
    if Expletive.profane?(value, @config) do
      {:error, "#{fieldname} is not allowed. Choose another #{String.downcase(fieldname)}"}
    else
      false
    end
  end
end
