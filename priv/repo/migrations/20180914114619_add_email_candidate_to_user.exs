defmodule Sanbase.Repo.Migrations.AddEmailCandidateToUser do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:email_candidate, :string)
    end
  end
end
