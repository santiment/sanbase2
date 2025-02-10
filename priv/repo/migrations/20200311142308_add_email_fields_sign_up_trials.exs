defmodule Sanbase.Repo.Migrations.AddEmailFieldsSignUpTrials do
  @moduledoc false
  use Ecto.Migration

  def up do
    alter table(:sign_up_trials) do
      remove(:sent_end_trial_email)
      add(:sent_first_education_email, :boolean, default: false)
      add(:sent_second_education_email, :boolean, default: false)
      add(:sent_cc_will_be_charged, :boolean, default: false)
      add(:sent_trial_finished_without_cc, :boolean, default: false)
    end
  end

  def down do
    alter table(:sign_up_trials) do
      remove(:sent_first_education_email)
      remove(:sent_second_education_email)
      remove(:sent_cc_will_be_charged)
      remove(:sent_trial_finished_without_cc)
      add(:sent_end_trial_email, :boolean, default: false)
    end
  end
end
