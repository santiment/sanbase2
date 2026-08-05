defmodule Sanbase.Billing.Plan.Bundle.CatalogTest do
  use Sanbase.DataCase, async: false

  import Ecto.Query
  import Mock

  alias Sanbase.Billing.Plan.Bundle.{Catalog, Package, Price}
  alias Sanbase.Repo
  alias Sanbase.StripeApi
  alias Sanbase.StripeApiTestResponse

  describe "ensure_local_catalog/0" do
    test "creates exactly 12 active rows for 6 SKUs × month/year" do
      assert {:ok, prices} = Catalog.ensure_local_catalog()
      assert length(prices) == 12

      month = Price.active("month")
      year = Price.active("year")
      assert length(month) == 6
      assert length(year) == 6

      assert Enum.map(month, & &1.sku) |> Enum.sort() ==
               Enum.sort(Package.slugs() ++ ["api_calls_500k"])
    end

    test "sets provisional package amounts and leaves the add-on unpriced" do
      assert {:ok, _} = Catalog.ensure_local_catalog()

      market = active!("market", "month")
      social = active!("social", "month")
      addon = active!("api_calls_500k", "month")

      assert market.amount == 35_000
      assert social.amount == 70_000
      assert addon.amount == nil
      assert addon.stripe_price_id == nil
    end

    test "is idempotent on a second call" do
      assert {:ok, first} = Catalog.ensure_local_catalog()
      assert {:ok, second} = Catalog.ensure_local_catalog()

      assert Enum.map(first, & &1.id) == Enum.map(second, & &1.id)
      assert length(Price.active("month")) == 6
      assert length(Price.active("year")) == 6
    end
  end

  describe "sync_with_stripe/0" do
    test "writes stripe_price_id for package rows and leaves the add-on unsynced" do
      with_mock StripeApi,
        find_bundle_product: fn _sku -> StripeApiTestResponse.find_bundle_product_resp(nil) end,
        create_bundle_product: fn name, metadata ->
          sku = metadata["sanbase_sku"]
          StripeApiTestResponse.create_bundle_product_resp(sku, name)
        end,
        create_bundle_price: fn attrs ->
          StripeApiTestResponse.create_price_resp(%{
            unit_amount: attrs.unit_amount,
            interval: attrs.interval,
            product: attrs.product,
            nickname: attrs.nickname,
            metadata: attrs.metadata
          })
        end do
        assert {:ok, synced} = Catalog.sync_with_stripe()
        assert length(synced) == 10

        assert Enum.all?(synced, fn p ->
                 p.type == :package and is_binary(p.stripe_price_id) and not is_nil(p.amount)
               end)

        addon = active!("api_calls_500k", "month")
        assert addon.amount == nil
        assert addon.stripe_price_id == nil

        assert Enum.map(Price.sellable("month"), & &1.sku) == Enum.sort(Package.slugs())
        assert Enum.map(Price.sellable("year"), & &1.sku) == Enum.sort(Package.slugs())
      end
    end

    test "does not create Stripe prices again for already-linked rows" do
      with_mock StripeApi,
        find_bundle_product: fn _sku -> StripeApiTestResponse.find_bundle_product_resp(nil) end,
        create_bundle_product: fn name, metadata ->
          StripeApiTestResponse.create_bundle_product_resp(metadata["sanbase_sku"], name)
        end,
        create_bundle_price: fn attrs ->
          StripeApiTestResponse.create_price_resp(%{
            unit_amount: attrs.unit_amount,
            interval: attrs.interval,
            product: attrs.product
          })
        end do
        assert {:ok, first} = Catalog.sync_with_stripe()
        assert length(first) == 10

        assert {:ok, second} = Catalog.sync_with_stripe()
        assert second == []

        assert_called_exactly(StripeApi.create_bundle_price(:_), 10)
      end
    end

    test "never creates a Stripe price for a row without an amount" do
      assert {:ok, _} = Catalog.ensure_local_catalog()

      create_price_calls = :counters.new(1, [])

      with_mock StripeApi,
        find_bundle_product: fn _sku -> StripeApiTestResponse.find_bundle_product_resp(nil) end,
        create_bundle_product: fn name, metadata ->
          StripeApiTestResponse.create_bundle_product_resp(metadata["sanbase_sku"], name)
        end,
        create_bundle_price: fn attrs ->
          :counters.add(create_price_calls, 1, 1)
          refute attrs.metadata["sanbase_sku"] == "api_calls_500k"

          StripeApiTestResponse.create_price_resp(%{
            unit_amount: attrs.unit_amount,
            interval: attrs.interval,
            product: attrs.product
          })
        end do
        assert {:ok, _} = Catalog.sync_with_stripe()
        assert :counters.get(create_price_calls, 1) == 10
      end
    end
  end

  describe "Sanbase.Billing.sync_bundle_catalog_with_stripe/0" do
    test "is the stage/prod entry point and syncs package prices" do
      with_mock StripeApi,
        find_bundle_product: fn _sku -> StripeApiTestResponse.find_bundle_product_resp(nil) end,
        create_bundle_product: fn name, metadata ->
          StripeApiTestResponse.create_bundle_product_resp(metadata["sanbase_sku"], name)
        end,
        create_bundle_price: fn attrs ->
          StripeApiTestResponse.create_price_resp(%{
            unit_amount: attrs.unit_amount,
            interval: attrs.interval,
            product: attrs.product
          })
        end do
        assert {:ok, synced} = Sanbase.Billing.sync_bundle_catalog_with_stripe()
        assert length(synced) == 10
        assert Enum.map(Price.sellable("month"), & &1.sku) == Enum.sort(Package.slugs())
      end
    end
  end

  defp active!(sku, interval) do
    from(p in Price, where: p.sku == ^sku and p.interval == ^interval and p.is_active)
    |> Repo.one!()
  end
end
