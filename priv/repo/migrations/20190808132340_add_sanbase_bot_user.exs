defmodule Sanbase.Repo.Migrations.AddSanbaseBotUser do
  use Ecto.Migration

  alias Sanbase.Accounts.User
  alias Sanbase.Repo

  def up do
    Application.ensure_all_started(:tzdata)

    %User{
      salt: User.generate_salt(),
      username: User.sanbase_bot_email(),
      email: User.sanbase_bot_email(),
      privacy_policy_accepted: true
    }
    |> Repo.insert!()
  end

  def down do
    Application.ensure_all_started(:tzdata)

    User
    |> Repo.get_by(email: User.sanbase_bot_email())
    |> Repo.delete()
  end
end
