defmodule Sanbase.Repo.Migrations.CreateAlphaNarativesEmailsTable do
  use Ecto.Migration

  def change do
    create table(:alpha_naratives_emails) do
      add(:email, :string)
      timestamps()
    end

    create(unique_index(:alpha_naratives_emails, [:email]))
  end
end
