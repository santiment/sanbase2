defmodule Sanbase.Repo.Migrations.AddUserLoginToken do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:email_token, :string)
      add(:email_token_generated_at, :naive_datetime)
    end

    create(unique_index(:users, [:email_token]))
  end
end
