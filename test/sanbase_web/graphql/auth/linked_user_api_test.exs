defmodule SanbaseWeb.Graphql.LinkedUserApiTest do
  use SanbaseWeb.ConnCase

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    insert(:project, slug: "bitcoin")

    user = insert(:user)
    pro_user = insert(:user)
    insert(:subscription_pro_sanbase, user: pro_user)

    conn = setup_jwt_auth(build_conn(), user)
    pro_conn = setup_jwt_auth(build_conn(), pro_user)

    %{
      user: user,
      pro_user: pro_user,
      conn: conn,
      pro_conn: pro_conn
    }
  end

  test "link two users", context do
    # The logged in user with the conn is primary, the other is the secondary user
    assert <<_::binary>> = token = generate_linked_user_token(context.pro_conn, context.user)

    assert true == confirm_linked_user_token(context.conn, token)

    assert current_user(context.conn) |> get_in(["primaryUser", "id"]) ==
             "#{context.pro_user.id}"

    assert current_user(context.pro_conn) |> get_in(["secondaryUsers"]) |> length() == 1

    assert current_user(context.pro_conn)
           |> get_in(["secondaryUsers", Access.at(0), "id"]) ==
             "#{context.user.id}"
  end

  test "unlink two users - primary removes secondary", context do
    token = generate_linked_user_token(context.pro_conn, context.user)
    true = confirm_linked_user_token(context.conn, token)
    true = remove_secondary_user(context.pro_conn, context.user.id)

    assert current_user(context.conn) |> get_in(["primaryUser", "id"]) == nil
    assert current_user(context.pro_conn) |> get_in(["secondaryUsers"]) == []
  end

  test "unlink two users - secondary removes primary", context do
    token = generate_linked_user_token(context.pro_conn, context.user)
    true = confirm_linked_user_token(context.conn, token)
    true = remove_primary_user(context.conn, context.pro_user.id)

    assert current_user(context.conn) |> get_in(["primaryUser", "id"]) == nil
    assert current_user(context.pro_conn) |> get_in(["secondaryUsers"]) == []
  end

  test "secondary user gets access to metrics", context do
    %{"errors" => [%{"message" => error_msg}]} = get_pro_metric(context.conn)
    assert error_msg =~ "parameters are outside the allowed interval"
    assert error_msg =~ "current subscription SANBASE free"

    token = generate_linked_user_token(context.pro_conn, context.user)
    true = confirm_linked_user_token(context.conn, token)

    assert %{"data" => %{"getMetric" => %{"timeseriesData" => data}}} =
             get_pro_metric(context.conn)

    assert is_list(data)
    assert length(data) > 0
  end

  # Private functions

  defp generate_linked_user_token(conn, secondary_user) do
    mutation = """
    mutation{
      generateLinkedUserToken(secondaryUserId: #{secondary_user.id})
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
    |> get_in(["data", "generateLinkedUserToken"])
  end

  defp confirm_linked_user_token(conn, token) do
    mutation = """
    mutation{
      confirmLinkedUserToken(token: "#{token}")
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
    |> get_in(["data", "confirmLinkedUserToken"])
  end

  defp remove_secondary_user(conn, secondary_user_id) do
    mutation = "mutation{ removeSecondaryUser(secondaryUserId: #{secondary_user_id}) }"

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
    |> get_in(["data", "removeSecondaryUser"])
  end

  defp remove_primary_user(conn, primary_user_id) do
    mutation = "mutation{ removePrimaryUser(PrimaryUserId: #{primary_user_id}) }"

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
    |> get_in(["data", "removePrimaryUser"])
  end

  defp current_user(conn) do
    query = """
    {
      currentUser{
        id
        email
        username
        primaryUserSanbaseSubscription{
          plan {
            product {
              name
            }
            name
          }
        }
        primaryUser {
          id
        }
        secondaryUsers {
          id
        }
        subscriptions {
          plan {
            product {
              name
            }
            name
          }
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "currentUser"])
  end

  defp get_pro_metric(conn) do
    map = %{datetime: DateTime.utc_now(), value: 5}

    Sanbase.Mock.prepare_mock2(&Sanbase.Metric.timeseries_data/6, {:ok, [map]})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = """
      {
        getMetric(metric: "mvrv_usd"){
          timeseriesData(slug: "bitcoin" from: "utc_now-3000d" to: "utc_now-2900d"){
            datetime value
          }
        }
      }
      """

      conn
      |> post("/graphql", query_skeleton(query))
      |> json_response(200)
    end)
  end
end
