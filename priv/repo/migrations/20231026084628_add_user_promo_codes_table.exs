defmodule Sanbase.Repo.Migrations.AddUserPromoCodeTable do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:user_promo_codes) do
      add(:user_id, references(:users, on_delete: :delete_all), null: false)

      add(:coupon, :string, null: false)
      add(:campaign, :string, null: true)
      add(:percent_off, :integer)
      add(:max_redemptions, :integer, default: 1)
      add(:times_redeemed, :integer, default: 0)
      add(:redeem_by, :utc_datetime)
      add(:metadata, :map, default_value: %{}, null: true)
      add(:extra_data, :map, default_value: %{}, null: true)

      # Will be set to false if max_redemptions is reached
      # or if redeem_by date is reached
      add(:valid, :boolean, null: false, default: true)

      timestamps()
    end

    create(unique_index(:user_promo_codes, [:coupon]))
  end
end
