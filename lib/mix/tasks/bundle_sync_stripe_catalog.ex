defmodule Mix.Tasks.Sanbase.Bundle.SyncStripeCatalog do
  @moduledoc """
  Local convenience wrapper. Prefer the module on stage/prod (no Mix there):

      Sanbase.Billing.sync_bundle_catalog_with_stripe()

  Or wait for `@reboot` `Sanbase.Billing.sync_products_with_stripe/0`.

      mix sanbase.bundle.sync_stripe_catalog
  """

  use Mix.Task

  @shortdoc "Sync bundle package catalog to Stripe Prices (local)"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    case Sanbase.Billing.sync_bundle_catalog_with_stripe() do
      {:ok, synced} ->
        Mix.shell().info("Synced #{length(synced)} bundle price(s) to Stripe.")

      {:error, reason} ->
        Mix.raise("Bundle Stripe catalog sync failed: #{inspect(reason)}")
    end
  end
end
