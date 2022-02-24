defmodule Sanbase.Repo.Migrations.PopulateSubscriptionSignUpTrials do
  use Ecto.Migration

  alias Sanbase.Billing.{Subscription, Product}
  alias Sanbase.Accounts.User

  alias Sanbase.Repo

  def up do
    setup()
    :ok
  end

  def down do
    :ok
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
    Application.ensure_all_started(:prometheus_ecto)
    Sanbase.Prometheus.EctoInstrumenter.setup()
  end
end
