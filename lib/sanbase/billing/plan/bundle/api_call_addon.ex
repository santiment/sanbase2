defmodule Sanbase.Billing.Plan.Bundle.ApiCallAddon do
  @moduledoc ~s"""
  The extra-API-call tiers that can be bought on top of a bundle.

  Every bundle comes with a flat monthly allowance regardless of how many
  packages were bought (§6.3 rule 2). Customers who need more buy one of these.

  Only the 500,000 tier is confirmed. Whether there are others is question Q4 in
  §15 of `docs/composable-api-plans-handover.md`; adding one is a single entry
  here plus a catalog row.
  """

  @type sku :: String.t()

  @type t :: %{
          sku: sku(),
          name: String.t(),
          calls_per_month: pos_integer()
        }

  @addons [
    %{
      sku: "api_calls_500k",
      name: "+500,000 API calls / month",
      calls_per_month: 500_000
    }
  ]

  @skus Enum.map(@addons, & &1.sku)

  @doc ~s"""
  Every add-on tier.
  """
  @spec all() :: [t()]
  def all, do: @addons

  @doc ~s"""
  The SKUs of all add-on tiers. These are the values stored in
  `subscription_items.sku` for items of type `:api_calls`.
  """
  @spec skus() :: [sku()]
  def skus, do: @skus

  @doc ~s"""
  Whether the given string names an add-on that is sold.
  """
  @spec valid_sku?(term()) :: boolean()
  def valid_sku?(sku) when is_binary(sku), do: sku in @skus
  def valid_sku?(_), do: false

  @doc ~s"""
  How many monthly calls one unit of this add-on grants.
  """
  @spec calls_per_month(term()) :: {:ok, pos_integer()} | {:error, String.t()}
  def calls_per_month(sku) when is_binary(sku) do
    case Enum.find(@addons, &(&1.sku == sku)) do
      nil ->
        {:error,
         "Unknown API call add-on #{inspect(sku)}. Known add-ons: #{Enum.join(@skus, ", ")}."}

      addon ->
        {:ok, addon.calls_per_month}
    end
  end

  def calls_per_month(sku), do: {:error, "Add-on SKU must be a string, got #{inspect(sku)}."}
end
