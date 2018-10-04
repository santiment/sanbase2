defmodule Sanbase.Repo.Migrations.AddEmailCandidateToUser do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:email_candidate_token, :string)
      add(:email_candidate_token_generated_at, :naive_datetime)
      add(:email_candidate_token_validated_at, :naive_datetime)
    end
  end
end
