defmodule Sanbase.Repo.Migrations.SanitizeUsersnames do
  use Ecto.Migration

  require Logger
  alias Sanbase.Auth.User
  alias Sanbase.Repo

  alias SanbaseWeb.Graphql.Helpers.Utils

  def change do
    Application.ensure_all_started(:tzdata)

    get_usernames()
    |> Enum.each(&trim_whitespace/1)

    get_usernames()
    |> filter_non_ascii()
    |> Enum.each(&update_to_nil/1)
  end

  def trim_whitespace(%{id: id, username: username}) do
    user = Repo.get(User, id)
    changeset = Ecto.Changeset.change(user, username: String.trim(username))

    case Repo.update(changeset) do
      {:ok, _struct} ->
        Logger.warn("Sanitize Usersnames: from: [#{user.username}] -> [#{String.trim(username)}]")

      {:error, _changeset} ->
        changeset = Ecto.Changeset.change(user, username: nil)
        Repo.update!(changeset)
        Logger.warn("Sanitize Usersnames: from: [#{user.username}] -> ['']")
    end
  end

  defp filter_non_ascii(usernames) do
    usernames
    |> Enum.reject(fn user -> user[:username] == nil end)
    |> Enum.reject(fn user ->
      user[:username]
      |> String.to_charlist()
      |> List.ascii_printable?()
    end)
  end

  defp get_usernames do
    User
    |> Repo.all()
    |> Enum.map(&Map.take(&1, [:id, :username]))
  end

  defp update_to_nil(%{id: id, username: username}) do
    user = Repo.get(User, id)
    changeset = Ecto.Changeset.change(user, username: "")

    case Repo.update(changeset) do
      {:ok, _struct} ->
        Logger.warn("Sanitize Usersnames: from: [#{username}] -> ['']")

      {:error, changeset} ->
        Logger.error(
          "Sanitize Usersnames: error sanitizing from: [#{user.username}] -> [''] | details: #{
            Utils.error_details(changeset)
          }"
        )
    end
  end
end
