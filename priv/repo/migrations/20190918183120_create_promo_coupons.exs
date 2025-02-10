defmodule Sanbase.Repo.Migrations.CreatePromoCoupons do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:promo_coupons) do
      add(:email, :string, null: false)
      add(:message, :text)
      add(:coupon, :string)
      add(:origin_url, :string)
    end

    create(unique_index(:promo_coupons, [:email]))
  end
end
