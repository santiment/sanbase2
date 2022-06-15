defmodule Sanbase.Repo.Migrations.SyncExchangeWalletsPlans do
  use Ecto.Migration

  import Ecto.Query
  alias Sanbase.Utils.Config
  alias Sanbase.Billing.{Product, Plan}
  alias Sanbase.Repo

  require Sanbase.Utils.Config

  def up do
    setup()
    stripe_api_key = stripe_api_key()

    if stripe_api_key != nil and stripe_api_key != "" do
      product_id = Product.product_exchange_wallets()

      from(p in Product, where: p.id == ^product_id)
      |> Repo.all()
      |> Enum.map(&Product.maybe_create_product_in_stripe/1)

      from(p in Plan, where: p.product_id == ^product_id)
      |> Repo.all()
      |> Repo.preload(:product)
      |> Enum.map(&Plan.maybe_create_plan_in_stripe/1)
    end
  end

  def down, do: :ok

  defp setup() do
    Application.ensure_all_started(:tzdata)
    Application.ensure_all_started(:stripity_stripe)
  end

  defp stripe_api_key() do
    Config.module_get(Sanbase.StripeConfig, :api_key)
  end
end
