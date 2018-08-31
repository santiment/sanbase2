defmodule Sanbase.Repo.Migrations.SanitizeUsernames do
  use Ecto.Migration

  require Logger
  alias Sanbase.Auth.User
  alias Sanbase.Repo

  alias SanbaseWeb.Graphql.Helpers.Utils

  def change do
    Application.ensure_all_started(:tzdata)

    work()
  end

  def work() do
    Logger.debug("trim_whitespace")

    all_users_non_nil_username()
    |> Enum.each(&trim_whitespace/1)

    Logger.debug("find_users_with_non_ascii")

    all_users_non_nil_username()
    |> find_users_with_non_ascii()
    |> Enum.each(&update_to_nil/1)
  end

  def all_users() do
    User
    |> Repo.all()
  end

  def all_users_non_nil_username() do
    all_users()
    |> Enum.reject(&(&1.username == nil))
  end

  defp trim_whitespace(%User{id: id, username: username}) do
    new_username = String.trim(username)
    Logger.debug("Sanitize Usersnames: Trying to trim: from: [#{username}] -> [#{new_username}]")

    update_with_new_username(id, username, new_username)
  end

  def update_with_new_username(_id, username, new_username) when username == new_username do
    :ok
  end

  def update_with_new_username(id, username, new_username) when username != new_username do
    user = Repo.get(User, id)
    changeset = User.changeset(user, %{username: new_username})

    case Repo.update(changeset) do
      {:ok, _struct} ->
        Logger.warn("Sanitize Usersnames: from: [#{username}] -> [#{new_username}]")

      {:error, changeset} ->
        Utils.error_details(changeset)
        changeset = User.changeset(user, %{username: nil})
        Repo.update!(changeset)
        Logger.warn("Sanitize Usersnames: from: [#{username}] -> [nil]")
    end
  end

  defp find_users_with_non_ascii(usernames) do
    usernames
    |> Enum.reject(fn user ->
      user.username
      |> User.ascii_username?()
    end)
  end

  defp update_to_nil(%User{id: id, username: username}) do
    user = Repo.get(User, id)
    changeset = User.changeset(user, %{username: nil})

    case Repo.update(changeset) do
      {:ok, _struct} ->
        Logger.warn("Sanitize Usersnames: from: [#{username}] -> [nil]")

      {:error, changeset} ->
        Logger.error(
          "Sanitize Usersnames: error sanitizing from: [#{user.username}] -> [nil] | details: #{
            Utils.error_details(changeset)
          }"
        )
    end
  end
end
