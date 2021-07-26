defmodule Sanbase.Repo.Migrations.AddIsFinishedSignUpTrials do
  use Ecto.Migration

  def change do
    alter table(:sign_up_trials) do
      add(:is_finished, :boolean, default: false)
    end
  end
end
