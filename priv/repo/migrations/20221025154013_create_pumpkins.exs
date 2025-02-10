defmodule Sanbase.Repo.Migrations.CreatePumpkins do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:pumpkins) do
      add(:collected, :integer, default: 0)
      add(:coupon, :string)
      add(:user_id, references(:users, on_delete: :delete_all))

      timestamps()
    end

    create(index(:pumpkins, [:user_id]))
  end
end
