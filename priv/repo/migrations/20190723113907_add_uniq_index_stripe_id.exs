defmodule Sanbase.Repo.Migrations.AddUniqIndexStripeId do
  @moduledoc false
  use Ecto.Migration

  def change do
    create(unique_index(:products, [:stripe_id]))

    create(unique_index(:plans, [:stripe_id]))

    create(unique_index(:subscriptions, [:stripe_id]))
  end
end
