defmodule Sanbase.Repo.Migrations.AddPromoTrialsTable do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:promo_trials) do
      add(:user_id, references(:users), null: false)
      add(:trial_days, :integer, null: false)
      add(:plans, {:array, :string}, null: false)

      timestamps()
    end
  end
end
