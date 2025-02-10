defmodule Sanbase.Repo.Migrations.CreatePlansAndProductsInStripe do
  @moduledoc false
  use Ecto.Migration

  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Product
  alias Sanbase.Repo
  alias Sanbase.Utils.Config

  require Sanbase.Utils.Config

  def up do
    Application.ensure_all_started(:tzdata)

    stripe_api_key = stripe_api_key()

    if stripe_api_key != nil and stripe_api_key != "" do
      Product |> Repo.all() |> Enum.map(&Product.maybe_create_product_in_stripe/1)

      Plan
      |> Repo.all()
      |> Repo.preload(:product)
      |> Enum.map(&Plan.maybe_create_plan_in_stripe/1)
    end
  end

  def down do
    :ok
  end

  defp stripe_api_key do
    Config.module_get(Sanbase.StripeConfig, :api_key)
  end
end
