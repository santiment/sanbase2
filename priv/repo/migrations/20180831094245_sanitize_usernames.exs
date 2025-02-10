defmodule Sanbase.Repo.Migrations.SanitizeUsernames do
  @moduledoc false
  use Ecto.Migration

  alias Sanbase.Accounts.User
  alias Sanbase.Repo
  alias SanbaseWeb.Graphql.Helpers.Utils

  require Logger

  def up do
    Application.ensure_all_started(:tzdata)

    work()
  end

  def down do
    :ok
  end

  def work do
    Logger.warning("trim_whitespace")

    Enum.each(all_users_non_nil_username(), &trim_whitespace/1)
    Logger.warning("find_users_with_non_ascii")

    all_users_non_nil_username()
    |> find_users_with_non_ascii()
    |> Enum.each(&update_to_nil/1)
  end

  def all_users do
    Repo.all(User)
  end

  def all_users_non_nil_username do
    Enum.reject(all_users(), &(&1.username == nil))
  end

  defp trim_whitespace(%User{id: id, username: username}) do
    new_username = String.trim(username)

    Logger.warning("Sanitize Usersnames: Trying to trim: from: [#{username}] -> [#{new_username}]")

    update_with_new_username(id, username, new_username)
  end

  def update_with_new_username(_id, username, new_username) when username == new_username do
    :ok
  end

  def update_with_new_username(id, username, new_username) when username != new_username do
    user = Repo.get(User, id)
    changeset = User.changeset(user, %{username: new_username})

    case Repo.get_by(User, username: new_username) do
      nil ->
        Logger.warning("Sanitize Usersnames: from: [#{username}] -> [#{new_username}]")
        Repo.update!(changeset)

      _ ->
        update_to_nil(user)
    end
  end

  defp find_users_with_non_ascii(usernames) do
    Enum.reject(usernames, fn user ->
      User.ascii_username?(user.username)
    end)
  end

  defp update_to_nil(%User{id: id, username: username}) do
    user = Repo.get(User, id)
    changeset = User.changeset(user, %{username: nil})

    Logger.warning("Sanitize Usersnames: from: [#{username}] -> [nil]")
    Repo.update!(changeset)
  end
end
