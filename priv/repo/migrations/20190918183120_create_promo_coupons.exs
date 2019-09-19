defmodule Sanbase.Repo.Migrations.CreatePromoCoupons do
  use Ecto.Migration

  def change do
    create table(:promo_coupons) do
      add(:email, :string, null: false)
      add(:message, :text)
      add(:coupon, :string)
    end

    create(unique_index(:promo_coupons, [:email]))
  end
end
