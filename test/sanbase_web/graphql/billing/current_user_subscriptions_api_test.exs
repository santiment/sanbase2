defmodule Sanbase.Billing.CurrentUserSubscriptionsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    %{user: user, conn: conn}
  end

  test "no subscriptions", context do
    subscriptions =
      context.conn
      |> current_user_subscriptions()
      |> get_in(["data", "currentUser", "subscriptions"])

    assert subscriptions == []
  end

  test "sanbase subscription", context do
    insert(:subscription_pro_sanbase,
      user: context.user,
      status: "active",
      type: :sanr_points_nft,
      current_period_end: DateTime.shift(DateTime.utc_now(), day: 20)
    )

    insert(:subscription_business_max_monthly,
      user: context.user,
      status: "active",
      type: :fiat
    )

    subscriptions =
      context.conn
      |> current_user_subscriptions()
      |> get_in(["data", "currentUser", "subscriptions"])

    assert %{
             "plan" => %{
               "name" => "BUSINESS_MAX",
               "product" => %{"name" => "Sanapi by Santiment"}
             },
             "type" => "FIAT"
           } in subscriptions

    assert %{
             "plan" => %{"name" => "PRO", "product" => %{"name" => "Sanbase by Santiment"}},
             "type" => "SANR_POINTS_NFT"
           } in subscriptions
  end

  defp current_user_subscriptions(conn) do
    query = """
    {
      currentUser{
        subscriptions{
          type
          plan {
            name
            product{
              name
            }
          }
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
