defmodule Sanbase.Repo.Migrations.CreatePlansAndProductsInStripe do
  use Ecto.Migration

  alias Sanbase.Pricing.{Product, Plan}
  alias Sanbase.Repo

  def up do
    Application.ensure_all_started(:tzdata)
    Application.ensure_all_started(:prometheus_ecto)
    Sanbase.Prometheus.EctoInstrumenter.setup()

    Product |> Repo.all() |> Enum.map(&Product.maybe_create_product_in_stripe/1)

    Plan |> Repo.all() |> Repo.preload(:product) |> Enum.map(&Plan.maybe_create_plan_in_stripe/1)
  end

  def down do
    :ok
  end
end
