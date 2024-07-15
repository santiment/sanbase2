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

  describe "anonymous user socket" do
    test "receive broadcast metric data" do
      # `jti` and `access_token` are not provided
      {:ok, socket} = connect(SanbaseWeb.UserSocket, %{})

      assert {:ok, %{}, _socket} =
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

    test "broadcasting is fast" do
      # This is a very basic test that does not test represent
      # the real world scenario.
      {:ok, socket} = connect(SanbaseWeb.UserSocket, %{})

      assert {:ok, %{}, _socket} =
               subscribe_and_join(socket, SanbaseWeb.MetricChannel, "metrics:price", %{})

      @endpoint.subscribe("metrics:price")

      list =
        Stream.cycle(data_map_list())
        |> Stream.map(fn data ->
          Map.put(data, "value", :rand.uniform())
        end)
        |> Enum.take(1000)

      {t_microseconds, _} =
        :timer.tc(fn ->
          for data_map <- list do
            SanbaseWeb.Endpoint.broadcast!(
              "metrics:price",
              "metric_data",
              data_map
            )
          end

          for data_map <- list do
            assert_push("metric_data", ^data_map)
          end
        end)

      t_ms = t_microseconds / 1000
      assert t_ms < 1000
    end
  end

  describe "user authenticated socket" do
    # Test that the metrics:price topic can be subscribed to by an anonymous user
    # No other channels are supporting access by anonymous users though.
    test "receive broadcast metric data", context do
      socket = get_socket(context.conn)

      assert {:ok, %{}, _socket} =
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

    test "receive broadcast metric data for some slugs only - unsubscribe works", context do
      socket = get_socket(context.conn)

      assert {:ok, %{}, socket} =
               subscribe_and_join(socket, SanbaseWeb.MetricChannel, "metrics:price", %{})

      # Initiate the channel no arguments (get all slugs) and unsubscribe from some of them
      unsubscribed_slugs = ["bitcoin", "ethereum"]
      push(socket, "unsubscribe_slugs", %{"slugs" => unsubscribed_slugs})

      @endpoint.subscribe("metrics:price")

      for data_map <- data_map_list() do
        SanbaseWeb.Endpoint.broadcast!(
          "metrics:price",
          "metric_data",
          data_map
        )
      end

      for data_map <- data_map_list() do
        if data_map["slug"] not in unsubscribed_slugs do
          assert_push("metric_data", ^data_map)
        else
          refute_push("metric_data", ^data_map)
        end
      end
    end

    test "receive broadcast metric data for some slugs only - subscribe works", context do
      socket = get_socket(context.conn)

      assert {:ok, %{}, socket} =
               subscribe_and_join(socket, SanbaseWeb.MetricChannel, "metrics:price", %{slugs: []})

      # Initiate the channel with no slugs (receive no data) and subscribe to some slugs
      subscribed_slugs = ["bitcoin", "ethereum"]
      push(socket, "subscribe_slugs", %{"slugs" => subscribed_slugs})

      @endpoint.subscribe("metrics:price")

      for data_map <- data_map_list() do
        SanbaseWeb.Endpoint.broadcast!(
          "metrics:price",
          "metric_data",
          data_map
        )
      end

      for data_map <- data_map_list() do
        if data_map["slug"] in subscribed_slugs do
          assert_push("metric_data", ^data_map)
        else
          refute_push("metric_data", ^data_map)
        end
      end
    end

    test "receive broadcast metric data for some metrics only - subscribe works", context do
      socket = get_socket(context.conn)

      assert {:ok, %{}, socket} =
               subscribe_and_join(socket, SanbaseWeb.MetricChannel, "metrics:price", %{
                 metrics: []
               })

      # Initiate the channel with no metrics (receive no data) and subscribe to some metrics
      subscribed_metrics = ["price_btc"]
      push(socket, "subscribe_metrics", %{"metrics" => subscribed_metrics})

      @endpoint.subscribe("metrics:price")

      for data_map <- data_map_list() do
        SanbaseWeb.Endpoint.broadcast!(
          "metrics:price",
          "metric_data",
          data_map
        )
      end

      for data_map <- data_map_list() do
        if data_map["metric"] in subscribed_metrics do
          assert_push("metric_data", ^data_map)
        else
          refute_push("metric_data", ^data_map)
        end
      end
    end

    test "receive broadcast metric data for some metrics only - unsubscribe works", context do
      socket = get_socket(context.conn)

      assert {:ok, %{}, socket} =
               subscribe_and_join(socket, SanbaseWeb.MetricChannel, "metrics:price", %{})

      unsubscribed_metrics = ["price_btc"]
      push(socket, "unsubscribe_metrics", %{"metrics" => unsubscribed_metrics})

      @endpoint.subscribe("metrics:price")

      for data_map <- data_map_list() do
        SanbaseWeb.Endpoint.broadcast!(
          "metrics:price",
          "metric_data",
          data_map
        )
      end

      for data_map <- data_map_list() do
        if data_map["metric"] not in unsubscribed_metrics do
          assert_push("metric_data", ^data_map)
        else
          refute_push("metric_data", ^data_map)
        end
      end
    end

    defp get_socket(conn) do
      {:ok, socket} =
        connect(
          SanbaseWeb.UserSocket,
          %{"access_token" => conn.private.plug_session["access_token"]}
        )

      socket
    end
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
        "metric" => "price_btc",
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
        "metric" => "price_btc",
        "slug" => "santiment",
        "datetime" => "2022-02-22T00:00:03Z",
        "value" => 16.18,
        "metadata" => %{"source" => "cryptocompare"}
      }
    ]
  end
end
