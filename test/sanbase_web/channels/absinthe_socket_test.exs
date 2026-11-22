defmodule SanbaseWeb.AbsintheSocketTest do
  @moduledoc """
  Regression tests for SECURITY_ANALYSIS.md C2.

  GraphQL documents pushed over the `/socket` websocket used to run outside the
  HTTP `/graphql` pipeline. Reproduced before the fix:

    * an anonymous socket could run queries;
    * the socket's authenticated user was not in the GraphQL context;
    * a query rejected over HTTP as "too complex" returned data over the socket;
    * a rate-limited user (429 over HTTP) still got data over the socket;
    * socket calls were neither exported to Kafka nor counted towards the quota.

  GraphQL is now served over HTTP only. Each scenario below asserts that the
  HTTP control still holds AND that the websocket bypass is closed: the
  Absinthe control topic (`__absinthe__:control`) is no longer routed, so no
  GraphQL document can be pushed over the socket at all.
  """
  use SanbaseWeb.ChannelCase

  import Sanbase.Factory

  @absinthe_control_topic "__absinthe__:control"
  @unmatched_topic_error ~r/no channel found for topic "__absinthe__:control"/

  defp anonymous_socket() do
    {:ok, socket} = connect(SanbaseWeb.UserSocket, %{})
    socket
  end

  defp authenticated_socket(user) do
    {:ok, %{access_token: access_token}} = SanbaseWeb.Guardian.get_jwt_tokens(user)
    {:ok, socket} = connect(SanbaseWeb.UserSocket, %{"access_token" => access_token})
    socket
  end

  # The real transport replies `unmatched topic` to a join for a topic the socket
  # does not route; `Phoenix.ChannelTest.join/2` raises for the same condition.
  defp assert_graphql_over_socket_rejected(socket) do
    assert SanbaseWeb.UserSocket.__channel__(@absinthe_control_topic) == nil

    assert_raise RuntimeError, @unmatched_topic_error, fn ->
      join(socket, @absinthe_control_topic)
    end
  end

  defp http_graphql(conn \\ Phoenix.ConnTest.build_conn(), query) do
    Phoenix.ConnTest.dispatch(conn, @endpoint, :post, "/graphql", %{"query" => query})
  end

  describe "the GraphQL entry point over the socket is closed" do
    test "for an anonymous socket" do
      assert_graphql_over_socket_rejected(anonymous_socket())
    end

    test "for an authenticated socket" do
      user = insert(:user)
      socket = authenticated_socket(user)

      # The socket still authenticates its user for the regular channels...
      assert socket.assigns.user_id == user.id

      # ...but cannot be used to run GraphQL.
      assert_graphql_over_socket_rejected(socket)
    end

    test "the regular user channels are still routed" do
      assert SanbaseWeb.UserSocket.__channel__("users:1") != nil
      assert SanbaseWeb.UserSocket.__channel__("notifications:1") != nil
      assert SanbaseWeb.UserSocket.__channel__("open_restricted_tabs:1") != nil
    end
  end

  test "a document rejected as too complex over HTTP cannot be run over the socket" do
    project = insert(:random_erc20_project)

    # Same shape as prices_api_test.exs "too complex queries are denied".
    query = """
    {
      historyPrice(
        slug: "#{project.slug}"
        from: "2010-01-01T21:45:00Z"
        to: "#{DateTime.utc_now() |> DateTime.to_iso8601()}"
        interval: "5m") {
          datetime
          priceUsd
      }
    }
    """

    # Stands in for the ClickHouse price query.
    rows = [
      %{
        datetime: ~U[2017-05-13 21:45:00Z],
        price_usd: 1700.0,
        price_btc: 1.0,
        marketcap_usd: 28_000_000_000,
        volume_usd: 1_000_000_000
      }
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.Price.timeseries_data/4, {:ok, rows})
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Price.first_datetime/1,
      {:ok, ~U[2010-01-01 00:00:00Z]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      # HTTP: denied by max_complexity, no data.
      http_result = http_graphql(query) |> Phoenix.ConnTest.json_response(200)

      assert [%{"message" => http_error} | _] = http_result["errors"]
      assert http_error =~ "too complex"
      assert http_result["data"] == nil

      # Socket: the bypass that used to return the rows is closed.
      assert_graphql_over_socket_rejected(anonymous_socket())
    end)
  end

  describe "API call accounting" do
    setup do
      Application.put_env(
        SanbaseWeb.Graphql.AbsintheBeforeSend,
        :api_call_exporting_enabled,
        true
      )

      on_exit(fn ->
        Application.delete_env(SanbaseWeb.Graphql.AbsintheBeforeSend, :api_call_exporting_enabled)
      end)

      # Deliver records an earlier test left in the exporter's buffer, so the
      # reset below clears them too.
      Sanbase.KafkaExporter.flush(:api_call_exporter)
      Sanbase.InMemoryKafka.Producer.clear_state()
      Sanbase.ApiCallLimit.ETS.clear_all()

      user = insert(:user, email: "socket_test@gmail.com")
      {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)
      insert(:random_project)

      %{user: user, apikey: apikey}
    end

    @all_projects_query "{ allProjects { slug } }"

    defp http_api_call(apikey) do
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("authorization", "Apikey " <> apikey)
      |> Plug.Conn.put_req_header("x-forwarded-for", "91.246.248.228")
      |> http_graphql(@all_projects_query)
    end

    defp exported_api_calls() do
      Sanbase.KafkaExporter.flush(:api_call_exporter)

      Sanbase.InMemoryKafka.Producer.get_state()
      |> Map.get("sanbase_api_call_data", [])
      |> Enum.map(fn {_key, data} -> Jason.decode!(data) end)
    end

    test "a rate-limited user is blocked over HTTP and cannot fall back to the socket",
         context do
      %{user: user, apikey: apikey} = context

      # Exhaust the free plan's per-minute quota (same setup as api_call_limit_api_test.exs).
      Sanbase.ApiCallLimit.update_usage(:user, :apikey, user, 200, 1000)

      # HTTP: 429.
      response = http_api_call(apikey)

      assert %{"errors" => %{"details" => details}} =
               Phoenix.ConnTest.json_response(response, 429)

      assert details =~ "API Rate Limit Reached"

      # Socket, same user: no GraphQL entry point to bypass the limit with.
      assert_graphql_over_socket_rejected(authenticated_socket(user))
    end

    test "HTTP API calls are exported to Kafka and counted; the socket offers no uncounted path",
         context do
      %{user: user, apikey: apikey} = context

      {:ok, %{api_calls_remaining: remaining_before_http}} =
        Sanbase.ApiCallLimit.get_quota(:user, user, :apikey)

      # HTTP: exported to the `api_call_exporter` Kafka topic and counted.
      assert %{"data" => %{"allProjects" => [_ | _]}} =
               http_api_call(apikey) |> Phoenix.ConnTest.json_response(200)

      http_exported = exported_api_calls()
      assert [%{"query" => "allProjects", "user_id" => user_id}] = http_exported
      assert user_id == user.id

      {:ok, %{api_calls_remaining: remaining_after_http}} =
        Sanbase.ApiCallLimit.get_quota(:user, user, :apikey)

      assert remaining_after_http.minute < remaining_before_http.minute

      # Socket: GraphQL cannot be pushed, so nothing runs uncounted.
      assert_graphql_over_socket_rejected(authenticated_socket(user))

      assert exported_api_calls() == http_exported

      assert {:ok, %{api_calls_remaining: ^remaining_after_http}} =
               Sanbase.ApiCallLimit.get_quota(:user, user, :apikey)
    end
  end
end
