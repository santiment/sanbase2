defmodule Sanbase.Repo.Migrations.CreateAnonymousUserInsights do
  use Ecto.Migration

  alias Sanbase.Accounts.User
  alias Sanbase.Repo

  def up do
    Application.ensure_all_started(:tzdata)

    %User{
      salt: User.generate_salt(),
      username: User.anonymous_user_username(),
      email: User.anonymous_user_email()
    }
    |> Repo.insert()
  end

  def down do
    Application.ensure_all_started(:tzdata)

    User
    |> Repo.get_by(username: User.anonymous_user_username())
    |> Repo.delete()
  end
end
