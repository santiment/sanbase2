defmodule Sanbase.Billing.Subscription.TimeseriesTest do
  use ExUnit.Case, async: true

  alias Sanbase.Billing.Subscription.Timeseries

  @sanapi_product "prod_FJtAemBs4HJ1P3"

  describe "extract_fields/1 with a legacy single-item subscription" do
    test "produces the same row it always has" do
      subscription =
        subscription(
          items: [
            item(
              plan:
                plan(id: "plan_pro", amount: 35_900, nickname: "PRO", product: @sanapi_product),
              price:
                price(
                  id: "price_pro",
                  unit_amount: 35_900,
                  nickname: "PRO",
                  product: @sanapi_product
                )
            )
          ]
        )

      assert Timeseries.extract_fields([subscription]) == [
               %{
                 id: "sub_legacy",
                 customer_id: "cus_legacy",
                 email: "user@example.com",
                 status: "active",
                 plan_nickname: "PRO",
                 product_name: "SanAPI by Santiment",
                 amount: 35_900,
                 latest_invoice_amount_due: 35_900,
                 latest_invoice_amount_paid: 35_900,
                 metadata: %{},
                 discount: nil,
                 start_date: ~U[2019-05-18 00:00:00Z],
                 end_date: nil,
                 trial_start: nil,
                 trial_end: nil
               }
             ]
    end

    test "is still classified as a SanAPI subscription" do
      subscription =
        subscription(
          items: [
            item(price: price(unit_amount: 35_900, product: @sanapi_product))
          ]
        )

      subscriptions =
        Timeseries.extract_fields([subscription])
        |> Timeseries.active_subscriptions()
        |> Timeseries.paid()
        |> Timeseries.product_name_starts_with("SanAPI")

      assert length(subscriptions) == 1
    end
  end

  describe "extract_fields/1 with a single Price-based item" do
    test "attributes to the price when the legacy plan object is missing" do
      subscription =
        subscription(
          items: [
            item(
              plan: nil,
              price: price(unit_amount: 35_000, nickname: "market/month", product: "prod_market")
            )
          ]
        )

      assert [row] = Timeseries.extract_fields([subscription])
      assert row.amount == 35_000
      assert row.plan_nickname == "market/month"
      assert row.product_name == "prod_market"
    end
  end

  describe "extract_fields/1 with a multi-item bundle subscription" do
    test "sums the amounts of all items instead of reporting one" do
      subscription =
        subscription(
          items: [
            item(id: "si_1", price: price(unit_amount: 35_000, product: @sanapi_product)),
            item(id: "si_2", price: price(unit_amount: 70_000, product: @sanapi_product))
          ]
        )

      assert [row] = Timeseries.extract_fields([subscription])
      assert row.amount == 105_000
    end

    test "multiplies each item amount by its quantity" do
      subscription =
        subscription(
          items: [
            item(id: "si_1", quantity: 1, price: price(unit_amount: 35_000)),
            item(id: "si_2", quantity: 3, price: price(unit_amount: 10_000))
          ]
        )

      assert [row] = Timeseries.extract_fields([subscription])
      assert row.amount == 65_000
    end

    test "does not depend on the order Stripe returns the items in" do
      first =
        item(id: "si_1", price: price(id: "price_1", unit_amount: 35_000, nickname: "market"))

      second =
        item(id: "si_2", price: price(id: "price_2", unit_amount: 70_000, nickname: "social"))

      assert Timeseries.extract_fields([subscription(items: [first, second])]) ==
               Timeseries.extract_fields([subscription(items: [second, first])])
    end

    test "an item with no price contributes nothing rather than raising" do
      subscription =
        subscription(
          items: [
            item(id: "si_1", price: price(unit_amount: 35_000)),
            item(id: "si_2", plan: nil, price: nil)
          ]
        )

      assert [row] = Timeseries.extract_fields([subscription])
      assert row.amount == 35_000
    end

    test "falls back to the legacy plan amount when only the plan is expanded" do
      subscription =
        subscription(
          items: [
            item(id: "si_1", price: price(unit_amount: 35_000)),
            item(id: "si_2", plan: plan(amount: 70_000), price: nil)
          ]
        )

      assert [row] = Timeseries.extract_fields([subscription])
      assert row.amount == 105_000
    end
  end

  describe "extract_fields/1 with an unusable item" do
    test "drops a subscription whose only item has neither plan nor price" do
      subscription = subscription(items: [item(plan: nil, price: nil)])

      assert Timeseries.extract_fields([subscription]) == []
    end

    test "drops a subscription with no items at all" do
      subscription = subscription(items: [])

      assert Timeseries.extract_fields([subscription]) == []
    end
  end

  defp subscription(opts) do
    %Stripe.Subscription{
      id: Keyword.get(opts, :id, "sub_legacy"),
      customer: %Stripe.Customer{
        id: "cus_legacy",
        email: Keyword.get(opts, :email, "user@example.com")
      },
      status: Keyword.get(opts, :status, "active"),
      metadata: %{},
      discount: nil,
      start_date: 1_558_185_786,
      ended_at: nil,
      trial_start: nil,
      trial_end: nil,
      latest_invoice: %Stripe.Invoice{amount_due: 35_900, amount_paid: 35_900},
      items: %Stripe.List{
        data: Keyword.fetch!(opts, :items),
        has_more: false,
        object: "list",
        total_count: length(Keyword.fetch!(opts, :items))
      }
    }
  end

  defp item(opts) do
    %Stripe.SubscriptionItem{
      id: Keyword.get(opts, :id, "si_1"),
      object: "subscription_item",
      metadata: %{},
      quantity: Keyword.get(opts, :quantity, 1),
      plan: Keyword.get(opts, :plan),
      price: Keyword.get(opts, :price),
      subscription: "sub_legacy"
    }
  end

  defp plan(opts) do
    %Stripe.Plan{
      id: Keyword.get(opts, :id, "plan_test"),
      object: "plan",
      amount: Keyword.get(opts, :amount),
      nickname: Keyword.get(opts, :nickname),
      product: Keyword.get(opts, :product, @sanapi_product)
    }
  end

  defp price(opts) do
    %Stripe.Price{
      id: Keyword.get(opts, :id, "price_test"),
      object: "price",
      unit_amount: Keyword.get(opts, :unit_amount),
      nickname: Keyword.get(opts, :nickname),
      product: Keyword.get(opts, :product, @sanapi_product)
    }
  end
end
