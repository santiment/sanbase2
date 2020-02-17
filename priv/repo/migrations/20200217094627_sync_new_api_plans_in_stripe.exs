defmodule Sanbase.Repo.Migrations.SyncNewApiPlansInStripe do
  use Ecto.Migration

  require Sanbase.Utils.Config

  alias Sanbase.Utils.Config
  alias Sanbase.Billing.{Product, Plan}
  alias Sanbase.Repo

  def up do
    setup()

    stripe_api_key = stripe_api_key()

    if stripe_api_key != nil and stripe_api_key != "" do
      Plan
      |> Repo.all()
      |> Repo.preload(:product)
      |> Enum.map(&Plan.maybe_create_plan_in_stripe/1)
    end
  end

  def down do
    :ok
  end

  defp stripe_api_key() do
    Config.module_get(Sanbase.StripeConfig, :api_key)
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
    Application.ensure_all_started(:prometheus_ecto)
    Application.ensure_all_started(:stripity_stripe)
    Sanbase.Prometheus.EctoInstrumenter.setup()
  end
end
