defmodule Sanbase.Repo.Migrations.AddMoreBotUsers do
  @moduledoc false
  use Ecto.Migration

  alias Sanbase.Accounts.User
  alias Sanbase.Repo

  def up do
    setup()

    Enum.each(1..8, fn idx ->
      Repo.insert!(%User{
        salt: User.generate_salt(),
        username: User.sanbase_bot_email(idx),
        email: User.sanbase_bot_email(idx),
        privacy_policy_accepted: true
      })
    end)
  end

  def down do
    setup()

    Enum.each(1..8, fn idx ->
      User
      |> Repo.get_by(email: User.sanbase_bot_email(idx))
      |> Repo.delete()
    end)
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
