defmodule Sanbase.Repo.Migrations.RemoveDuplicatedUsernames do
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Auth.User
  alias Sanbase.Repo

  def up do
    users = Repo.all(User)

    duplicated_usernames =
      users
      |> Enum.map(fn %User{username: username} -> username end)
      |> Enum.reject(fn username -> username == nil or username == "" end)
      |> duplicates()

    users_to_update =
      users
      |> Enum.map(fn %User{username: username} = user ->
        if username in duplicated_usernames do
          User.changeset(user, %{username: nil})
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    users_to_update
    |> Enum.each(&Repo.update/1)
  end

  def down do
    :ok
  end

  # Private functions

  defp duplicates(list) do
    list
    |> Enum.reduce(%{}, fn el, acc -> Map.update(acc, el, 1, &(&1 + 1)) end)
    |> Enum.filter(fn {key, val} -> val > 1 end)
    |> Enum.map(fn {key, val} -> key end)
  end
end
