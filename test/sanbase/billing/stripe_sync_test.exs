defmodule Sanbase.Billing.StripeSyncTest do
  use Sanbase.DataCase, async: false

  import Mock

  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Product
  alias Sanbase.Billing.StripeSync

  describe "transactions/1 plan and product attribution" do
    test "a legacy single-item subscription attributes to the item's plan" do
      charge = charge(items: [item(plan: plan_object("plan_pro", "prod_sanapi"), price: nil)])

      assert [transaction] = transactions([charge])
      assert transaction.plan == "plan_pro"
      assert transaction.product == "prod_sanapi"
    end

    test "a single Price-based item attributes to the price" do
      charge =
        charge(items: [item(plan: nil, price: price_object("price_market", "prod_market"))])

      assert [transaction] = transactions([charge])
      assert transaction.plan == "price_market"
      assert transaction.product == "prod_market"
    end

    test "a two-item bundle subscription is marked instead of attributed to one item" do
      charge =
        charge(
          items: [
            item(id: "si_1", plan: nil, price: price_object("price_market", "prod_market")),
            item(id: "si_2", plan: nil, price: price_object("price_social", "prod_social"))
          ]
        )

      assert [transaction] = transactions([charge])
      assert transaction.plan == "MULTI_ITEM_SUBSCRIPTION"
      assert transaction.product == "MULTI_ITEM_SUBSCRIPTION"
    end

    test "an item with neither plan nor price attributes to nothing" do
      charge = charge(items: [item(plan: nil, price: nil)])

      assert [transaction] = transactions([charge])
      assert transaction.plan == nil
      assert transaction.product == nil
    end

    test "a subscription with no items attributes to nothing" do
      charge = charge(items: [])

      assert [transaction] = transactions([charge])
      assert transaction.plan == nil
      assert transaction.product == nil
    end

    test "a charge with no invoice attributes to nothing" do
      charge = %{charge(items: []) | invoice: nil}

      assert [transaction] = transactions([charge])
      assert transaction.plan == nil
      assert transaction.product == nil
    end

    test "the other transaction fields are untouched" do
      charge = charge(items: [item(plan: plan_object("plan_pro", "prod_sanapi"), price: nil)])

      assert [transaction] = transactions([charge])

      assert transaction == %{
               id: "ch_test",
               status: "succeeded",
               created_at: 1_558_185_786,
               amount: 359.0,
               customer: "cus_test",
               plan: "plan_pro",
               product: "prod_sanapi"
             }
    end
  end

  describe "sync_all_transactions/1" do
    setup do
      Sanbase.InMemoryKafka.Producer.clear_state()

      {:ok, plan} =
        Plan
        |> Sanbase.Repo.get(3)
        |> Ecto.Changeset.change(stripe_id: "plan_pro")
        |> Sanbase.Repo.update()

      {:ok, product} =
        Product
        |> Sanbase.Repo.get(1)
        |> Ecto.Changeset.change(stripe_id: "prod_sanapi")
        |> Sanbase.Repo.update()

      %{plan: plan, product: product}
    end

    test "resolves a legacy charge to the local plan and product names", context do
      charge = charge(items: [item(plan: plan_object("plan_pro", "prod_sanapi"), price: nil)])

      assert [data] = exported_data([charge])
      assert data["plan"] == context.plan.name
      assert data["product"] == context.product.name
    end

    test "keeps the multi-item marker instead of nulling it in the id to name lookup" do
      charge =
        charge(
          items: [
            item(id: "si_1", plan: nil, price: price_object("price_market", "prod_market")),
            item(id: "si_2", plan: nil, price: price_object("price_social", "prod_social"))
          ]
        )

      assert [data] = exported_data([charge])
      assert data["plan"] == "MULTI_ITEM_SUBSCRIPTION"
      assert data["product"] == "MULTI_ITEM_SUBSCRIPTION"
    end

    test "an unknown stripe plan id still resolves to nothing" do
      charge =
        charge(items: [item(plan: plan_object("plan_unknown", "prod_unknown"), price: nil)])

      assert [data] = exported_data([charge])
      assert data["plan"] == nil
      assert data["product"] == nil
    end
  end

  defp transactions(charges) do
    with_mock Stripe.Charge, [:passthrough],
      list: fn _params, _opts -> {:ok, list(charges)} end do
      StripeSync.transactions()
    end
  end

  # Yesterday's beginning of day makes `sync_all_transactions/1` iterate over
  # exactly one day, so the mocked charge list is consumed once.
  defp exported_data(charges) do
    start_dt = Timex.now() |> Timex.shift(days: -1) |> Timex.beginning_of_day()

    with_mock Stripe.Charge, [:passthrough],
      list: fn _params, _opts -> {:ok, list(charges)} end do
      StripeSync.sync_all_transactions(start_dt)
    end

    Sanbase.InMemoryKafka.Producer.get_state()
    |> Map.get("sanbase_stripe_transactions", [])
    |> Enum.map(fn {_key, value} ->
      value |> Jason.decode!() |> Map.get("data") |> Jason.decode!()
    end)
  end

  defp list(charges) do
    %Stripe.List{
      data: charges,
      has_more: false,
      object: "list",
      total_count: length(charges),
      url: "/v1/charges"
    }
  end

  defp charge(opts) do
    items = Keyword.fetch!(opts, :items)

    %Stripe.Charge{
      id: "ch_test",
      object: "charge",
      status: "succeeded",
      created: 1_558_185_786,
      amount: 35_900,
      customer: "cus_test",
      invoice: %Stripe.Invoice{
        id: "in_test",
        subscription: %Stripe.Subscription{
          id: "sub_test",
          items: %Stripe.List{
            data: items,
            has_more: false,
            object: "list",
            total_count: length(items)
          }
        }
      }
    }
  end

  defp item(opts) do
    %Stripe.SubscriptionItem{
      id: Keyword.get(opts, :id, "si_1"),
      object: "subscription_item",
      metadata: %{},
      quantity: 1,
      plan: Keyword.get(opts, :plan),
      price: Keyword.get(opts, :price),
      subscription: "sub_test"
    }
  end

  defp plan_object(id, product) do
    %Stripe.Plan{id: id, object: "plan", product: product, amount: 35_900, nickname: nil}
  end

  defp price_object(id, product) do
    %Stripe.Price{id: id, object: "price", product: product, unit_amount: 35_900, nickname: nil}
  end
end
