defmodule Sanbase.Repo.Migrations.CreateUserUniswapStaking do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:user_uniswap_staking) do
      add(:san_staked, :float)
      add(:user_id, references(:users, on_delete: :delete_all))

      timestamps()
    end

    create(unique_index(:user_uniswap_staking, [:user_id]))
  end
end
