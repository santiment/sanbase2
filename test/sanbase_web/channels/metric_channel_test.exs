defmodule SanbaseWeb.MetricChannelTest do
  use SanbaseWeb.ChannelCase

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    user2 = insert(:user)
    conn = setup_jwt_auth(Phoenix.ConnTest.build_conn(), user)
    conn2 = setup_jwt_auth(Phoenix.ConnTest.build_conn(), user2)

    %{user: user, user2: user2, conn: conn, conn2: conn2}
  end

  test "multiple users in a channel receive metrics", context do
    socket = get_socket(context.conn, context.user)

    assert {:ok, %{}, %Phoenix.Socket{}} =
             subscribe_and_join(socket, SanbaseWeb.MetricChannel, "metrics:price", %{})

    @endpoint.subscribe("metrics:price")

    for data_map <- data_map_list() do
      SanbaseWeb.Endpoint.broadcast!(
        "metrics:price",
        "metric_data",
        data_map
      )
    end

    for data_map <- data_map_list() do
      assert_push("metric_data", ^data_map)
    end
  end

  defp get_socket(conn, _user) do
    {:ok, socket} =
      connect(
        SanbaseWeb.UserSocket,
        %{"access_token" => conn.private.plug_session["access_token"]},
        %{}
      )

    socket
  end

  defp data_map_list do
    [
      %{
        "metric" => "price_usd",
        "slug" => "bitcoin",
        "datetime" => "2022-02-22T00:00:00Z",
        "value" => 54000.0,
        "metadata" => %{"source" => "cryptocompare"}
      },
      %{
        "metric" => "price_usd",
        "slug" => "ethereum",
        "datetime" => "2022-02-22T00:00:00Z",
        "value" => 2500.0,
        "metadata" => %{"source" => "cryptocompare"}
      },
      %{
        "metric" => "price_usd",
        "slug" => "bitcoin",
        "datetime" => "2022-02-22T00:00:02Z",
        "value" => 54040.0,
        "metadata" => %{"source" => "cryptocompare"}
      },
      %{
        "metric" => "price_usd",
        "slug" => "ethereum",
        "datetime" => "2022-02-22T00:00:03Z",
        "value" => 2505.0,
        "metadata" => %{"source" => "cryptocompare"}
      }
    ]
  end
end
