defmodule Sanbase.Repo.Migrations.AddSubscriptionIdsToPromoTrials do
  use Ecto.Migration

  def change do
    alter table(:promo_trials) do
      add(:subscription_ids, {:array, :integer}, null: false, default: [])
    end
  end
end
