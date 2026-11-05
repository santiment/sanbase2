defmodule SanbaseWeb.Graphql.Billing.BusinessAllowanceApiTest do
  @moduledoc ~s"""
  `apiCallLimits` of a Business plan read through a customer's subscription answers
  for that subscription, while the same plan in the catalog answers for someone
  subscribing now. See `Sanbase.ApiCallLimit.BusinessAllowance`.
  """

  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.FeatureToggle
  alias Sanbase.Repo

  setup context do
    Repo.insert!(
      %FeatureToggle{
        name: FeatureToggle.business_reduced_api_calls_name(),
        enabled: true,
        enabled_at: ~U[2026-11-01 00:00:00Z]
      },
      on_conflict: {:replace, [:enabled, :enabled_at]},
      conflict_target: :name
    )

    user = insert(:user, email: "business#{System.unique_integer([:positive])}@example.com")

    %{
      user: user,
      conn: setup_jwt_auth(build_conn(), user),
      pro: context.plans.plan_business_pro_monthly
    }
  end

  test "a grandfathered subscription shows the old monthly figure", context do
    subscribe(context, ~N[2026-10-15 12:00:00])

    assert subscription_month(context.conn) == 600_000
  end

  test "a subscription from the cutoff on shows the reduced figure", context do
    subscribe(context, ~N[2026-11-02 12:00:00])

    assert subscription_month(context.conn) == 50_000
  end

  test "the catalog shows the reduced figure for someone subscribing now", context do
    query = """
    {
      productsWithPlans {
        plans { name apiCallLimits { month } }
      }
    }
    """

    months =
      context.conn
      |> execute_query(query, "productsWithPlans")
      |> Enum.flat_map(& &1["plans"])
      |> Enum.filter(&(&1["name"] == "BUSINESS_PRO"))
      |> Enum.map(&get_in(&1, ["apiCallLimits", "month"]))

    assert months != []
    assert Enum.all?(months, &(&1 == 50_000))
  end

  defp subscribe(context, inserted_at) do
    insert(:subscription_pro,
      user: context.user,
      plan_id: context.pro.id,
      status: :active,
      stripe_id: "sub_" <> Ecto.UUID.generate(),
      inserted_at: inserted_at
    )
  end

  defp subscription_month(conn) do
    query = """
    {
      currentUser {
        subscriptions {
          plan { name apiCallLimits { month } }
        }
      }
    }
    """

    conn
    |> execute_query(query, "currentUser")
    |> Map.fetch!("subscriptions")
    |> Enum.find(&(&1["plan"]["name"] == "BUSINESS_PRO"))
    |> get_in(["plan", "apiCallLimits", "month"])
  end
end
