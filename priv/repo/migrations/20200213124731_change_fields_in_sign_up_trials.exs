defmodule Sanbase.Repo.Migrations.ChangeFieldsInSignUpTrials do
  @moduledoc false
  use Ecto.Migration

  def up do
    alter table(:sign_up_trials) do
      remove(:sent_3day_email)
      remove(:sent_11day_email)
      add(:sent_trial_will_end_email, :boolean, default: false)
      add(:subscription_id, references(:subscriptions))
    end

    create(unique_index(:sign_up_trials, [:subscription_id]))
  end

  def down do
    drop(unique_index(:sign_up_trials, [:subscription_id]))

    alter table(:sign_up_trials) do
      remove(:sent_trial_will_end_email)
      remove(:subscription_id)
      add(:sent_3day_email, :boolean, default: false)
      add(:sent_11day_email, :boolean, default: false)
    end
  end
end
