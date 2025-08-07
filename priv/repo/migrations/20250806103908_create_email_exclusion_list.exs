defmodule Sanbase.Repo.Migrations.CreateEmailExclusionList do
  use Ecto.Migration

  def change do
    create table(:email_exclusion_list) do
      add(:email, :string, null: false)
      add(:reason, :text)

      timestamps()
    end

    create(unique_index(:email_exclusion_list, [:email]))
  end
end
