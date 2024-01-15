defmodule Sanbase.Repo.Migrations.CreateSanrEmailsTable do
  use Ecto.Migration

  def change do
    create table(:sanr_emails) do
      add(:email, :string)
      timestamps()
    end

    create(unique_index(:sanr_emails, [:email]))
  end
end
