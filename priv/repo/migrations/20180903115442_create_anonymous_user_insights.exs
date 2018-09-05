defmodule Sanbase.Repo.Migrations.CreateAnonymousUserInsights do
  use Ecto.Migration

  alias Sanbase.Auth.User
  alias Sanbase.Repo

  def up do
    Application.ensure_all_started(:tzdata)

    %User{
      salt: User.generate_salt(),
      username: User.insights_fallback_username(),
      email: User.insights_fallback_email()
    }
    |> Repo.insert()
  end

  def down do
    Application.ensure_all_started(:tzdata)

    User
    |> Repo.get_by(username: User.insights_fallback_username())
    |> Repo.delete()
  end
end
