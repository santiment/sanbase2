defmodule Sanbase.Repo.Migrations.CreateSignUpTrials do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:sign_up_trials) do
      add(:user_id, references(:users, on_delete: :delete_all))
      add(:sent_welcome_email, :boolean, default: false)
      add(:sent_3day_email, :boolean, default: false)
      add(:sent_11day_email, :boolean, default: false)
      add(:sent_end_trial_email, :boolean, default: false)

      timestamps()
    end

    create(index(:sign_up_trials, [:user_id]))
  end
end
