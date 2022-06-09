defmodule Sanbase.Repo.Migrations.AddMoreBotUsers do
  use Ecto.Migration

  alias Sanbase.Accounts.User
  alias Sanbase.Repo

  def up do
    setup()

    1..8
    |> Enum.each(fn idx ->
      %User{
        salt: User.generate_salt(),
        username: User.sanbase_bot_email(idx),
        email: User.sanbase_bot_email(idx),
        privacy_policy_accepted: true
      }
      |> Repo.insert!()
    end)
  end

  def down do
    setup()

    1..8
    |> Enum.each(fn idx ->
      User
      |> Repo.get_by(email: User.sanbase_bot_email(idx))
      |> Repo.delete()
    end)
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
