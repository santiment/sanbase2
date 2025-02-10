defmodule Sanbase.Repo.Migrations.AddEmailCandidateToUser do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:email_candidate, :string)
    end
  end
end
