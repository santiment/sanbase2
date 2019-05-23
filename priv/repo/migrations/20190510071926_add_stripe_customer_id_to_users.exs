defmodule Sanbase.Repo.Migrations.AddStripeCustomerIdToUsers do
  use Ecto.Migration

  @table :users
  def up do
    alter table(@table) do
      add(:stripe_customer_id, :string)
    end

    create(unique_index(@table, [:stripe_customer_id]))
  end

  def down do
    alter table(@table) do
      remove(:stripe_customer_id)
    end
  end
end
