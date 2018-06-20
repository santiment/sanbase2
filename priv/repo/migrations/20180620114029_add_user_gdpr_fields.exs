defmodule Sanbase.Repo.Migrations.AddUserGdprFields do
  use Ecto.Migration

  # Add two GDPR related fields.
  #
  # If `privacy_policy_accepted` is `false` the user
  # should be restricted until he or she accepts the privacy policy
  #
  # `marketing_accepted` marks whether or not the user likes to receive marketing materials
  # This field's value does not restrict the user's actions.

  def change do
    alter table(:users) do
      add(:privacy_policy_accepted, :boolean, null: false, default: false)
      add(:marketing_accepted, :boolean, null: false, default: false)
    end
  end
end
