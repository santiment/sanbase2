defmodule Sanbase.Repo.Migrations.AddTestSanBalanceToUser do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:test_san_balance, :numeric)
    end
  end
end
