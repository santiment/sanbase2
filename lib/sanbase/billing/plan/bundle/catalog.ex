defmodule Sanbase.Billing.Plan.Bundle.Catalog do
  @moduledoc ~s"""
  The sellable Stripe catalog for bundle packages and API-call add-ons.

  Local rows live in `bundle_prices`. Stripe Products/Prices are created by
  `sync_with_stripe/0`, invoked in production via
  `Sanbase.Billing.sync_bundle_catalog_with_stripe/0` or as part of
  `Sanbase.Billing.sync_products_with_stripe/0` (`@reboot`). Idempotent: skips
  rows with no amount and rows that already have a `stripe_price_id`.

  ## Twelve rows

  Five packages + `api_calls_500k`, each as month and year. Package amounts are
  provisional (pricing mock). The add-on keeps `amount: nil` until product sets
  a price; sync skips it until then.
  """

  import Ecto.Query

  alias Sanbase.Billing.Plan.Bundle.{ApiCallAddon, Package, Price}
  alias Sanbase.Repo
  alias Sanbase.StripeApi

  @type entry :: %{
          sku: String.t(),
          type: :package | :api_calls,
          interval: String.t(),
          amount: non_neg_integer() | nil
        }

  # Amounts in cents. Changeable via Price.replace/1 after a Stripe id exists.
  @entries [
    %{sku: "market", type: :package, interval: "month", amount: 35_000},
    %{sku: "market", type: :package, interval: "year", amount: 350_000},
    %{sku: "development", type: :package, interval: "month", amount: 35_000},
    %{sku: "development", type: :package, interval: "year", amount: 350_000},
    %{sku: "social", type: :package, interval: "month", amount: 70_000},
    %{sku: "social", type: :package, interval: "year", amount: 700_000},
    %{sku: "onchain_core", type: :package, interval: "month", amount: 40_000},
    %{sku: "onchain_core", type: :package, interval: "year", amount: 400_000},
    %{sku: "onchain_labels", type: :package, interval: "month", amount: 40_000},
    %{sku: "onchain_labels", type: :package, interval: "year", amount: 400_000},
    %{sku: "api_calls_500k", type: :api_calls, interval: "month", amount: nil},
    %{sku: "api_calls_500k", type: :api_calls, interval: "year", amount: nil}
  ]

  @doc ~s"""
  The catalog definition: 6 SKUs × month/year.
  """
  @spec entries() :: [entry()]
  def entries, do: @entries

  @doc ~s"""
  Ensure every catalog entry has an active local `bundle_prices` row.

  - Missing row → insert.
  - Existing row with no Stripe id → refresh provisional `amount` from `@entries`.
  - Existing row that already has a Stripe id → leave alone (use `Price.replace/1`
    for real price changes).
  """
  @spec ensure_local_catalog() :: {:ok, [Price.t()]} | {:error, Ecto.Changeset.t()}
  def ensure_local_catalog do
    Enum.reduce_while(@entries, {:ok, []}, fn entry, {:ok, acc} ->
      case ensure_row(entry) do
        {:ok, price} -> {:cont, {:ok, [price | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, prices} -> {:ok, Enum.reverse(prices)}
      error -> error
    end
  end

  @doc ~s"""
  Create missing Stripe Products/Prices and write `stripe_price_id` on local rows.

  Skips rows with `amount: nil` and rows that already have a Stripe price id.
  Idempotent: a second run does not create duplicate Stripe objects for linked rows.
  """
  @spec sync_with_stripe() :: {:ok, [Price.t()]} | {:error, term()}
  def sync_with_stripe do
    with {:ok, _} <- ensure_local_catalog() do
      rows_needing_sync()
      |> Enum.reduce_while({:ok, %{}, []}, fn price, {:ok, products, synced} ->
        case sync_row(price, products) do
          {:ok, updated, products} -> {:cont, {:ok, products, [updated | synced]}}
          {:error, _} = error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, _products, synced} -> {:ok, Enum.reverse(synced)}
        error -> error
      end
    end
  end

  defp ensure_row(%{sku: sku, interval: interval, amount: amount} = entry) do
    case get_active(sku, interval) do
      nil ->
        Price.create(Map.take(entry, [:sku, :type, :interval, :amount]))

      %Price{stripe_price_id: nil} = price ->
        if price.amount == amount do
          {:ok, price}
        else
          price
          |> Price.changeset(%{amount: amount})
          |> Repo.update()
        end

      %Price{} = price ->
        {:ok, price}
    end
  end

  defp rows_needing_sync do
    from(p in Price,
      where: p.is_active and not is_nil(p.amount) and is_nil(p.stripe_price_id),
      order_by: [asc: p.type, asc: p.sku, asc: p.interval]
    )
    |> Repo.all()
  end

  defp sync_row(%Price{} = price, products) do
    with {:ok, product_id, products} <- ensure_stripe_product(price.sku, products),
         {:ok, stripe_price} <-
           StripeApi.create_bundle_price(%{
             nickname: price_nickname(price),
             currency: String.downcase(price.currency),
             unit_amount: price.amount,
             interval: price.interval,
             product: product_id,
             metadata: %{
               "sanbase_sku" => price.sku,
               "sanbase_interval" => price.interval
             }
           }),
         {:ok, updated} <-
           price
           |> Price.changeset(%{stripe_price_id: stripe_price.id})
           |> Repo.update() do
      {:ok, updated, products}
    end
  end

  defp ensure_stripe_product(sku, products) do
    case Map.fetch(products, sku) do
      {:ok, product_id} ->
        {:ok, product_id, products}

      :error ->
        with {:ok, existing} <- StripeApi.find_bundle_product(sku),
             {:ok, product_id} <- create_or_use_product(sku, existing) do
          {:ok, product_id, Map.put(products, sku, product_id)}
        end
    end
  end

  defp create_or_use_product(_sku, %Stripe.Product{id: id}), do: {:ok, id}

  defp create_or_use_product(sku, nil) do
    case StripeApi.create_bundle_product(display_name(sku), %{"sanbase_sku" => sku}) do
      {:ok, %Stripe.Product{id: id}} -> {:ok, id}
      {:error, _} = error -> error
    end
  end

  defp display_name(sku) do
    case Package.by_slug(sku) do
      {:ok, package} ->
        package.name

      {:error, _} ->
        case Enum.find(ApiCallAddon.all(), &(&1.sku == sku)) do
          nil -> sku
          addon -> addon.name
        end
    end
  end

  defp price_nickname(%Price{sku: sku, interval: interval}) do
    "#{display_name(sku)} (#{interval})"
  end

  defp get_active(sku, interval) do
    from(p in Price, where: p.sku == ^sku and p.interval == ^interval and p.is_active)
    |> Repo.one()
  end
end
