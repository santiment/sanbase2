defmodule SanbaseWeb.Graphql.Clickhouse.ApiSignalTimeseriesDataTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Signal

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    insert(:random_project, slug: "ethereum")

    [
      conn: conn,
      slug: "ethereum",
      from: ~U[2019-01-01 00:00:00Z],
      to: ~U[2019-01-02 00:00:00Z],
      interval: "1d"
    ]
  end

  test "returns data for an available signal", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    aggregation = :avg
    [signal | _] = Signal.available_signals()

    rows = [
      [
        DateTime.to_unix(~U[2019-01-01 00:00:00Z]),
        2,
        [
          ~s({"txHash": "0xecdeb8435aff6e18e08177bb94d52b2da6dd15b95aee7f442021911a7c9861e6", "address": "0x183c9077fb7b74f02d3badda6c85a19c92b1f648"}),
          ~s({"txHash": "0x8e8eae8adeb2fae2b21387d7bea7f4287e425cfe9efc1728966eceed4feb7d4e", "address": "0x65b0bf8ee4947edd2a500d74e50a3d757dc79de0"})
        ]
      ],
      [
        DateTime.to_unix(~U[2019-01-02 00:00:00Z]),
        1,
        [
          ~s({"txHash": "0x0bb27622fa4fcdf39344251e9b0776467eaa5d9dbf0f025d254f55093848f2bd", "address": "0x61c808d82a3ac53231750dadc13c777b59310bd9"})
        ]
      ]
    ]

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        conn
        |> get_timeseries_signal(signal, slug, from, to, interval, aggregation)
        |> extract_timeseries_data()

      assert result == [
               %{
                 "value" => 2,
                 "datetime" => "2019-01-01T00:00:00Z",
                 "metadata" => [
                   %{
                     "address" => "0x183c9077fb7b74f02d3badda6c85a19c92b1f648",
                     "txHash" => "0xecdeb8435aff6e18e08177bb94d52b2da6dd15b95aee7f442021911a7c9861e6"
                   },
                   %{
                     "address" => "0x65b0bf8ee4947edd2a500d74e50a3d757dc79de0",
                     "txHash" => "0x8e8eae8adeb2fae2b21387d7bea7f4287e425cfe9efc1728966eceed4feb7d4e"
                   }
                 ]
               },
               %{
                 "value" => 1,
                 "datetime" => "2019-01-02T00:00:00Z",
                 "metadata" => [
                   %{
                     "address" => "0x61c808d82a3ac53231750dadc13c777b59310bd9",
                     "txHash" => "0x0bb27622fa4fcdf39344251e9b0776467eaa5d9dbf0f025d254f55093848f2bd"
                   }
                 ]
               }
             ]
    end)
  end

  test "returns data for all available signals", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    aggregation = :avg
    signals = Signal.available_signals()

    (&Signal.timeseries_data/6)
    |> Sanbase.Mock.prepare_mock2(
      {:ok,
       [
         %{value: 100.0, datetime: ~U[2019-01-01 00:00:00Z], metadata: []},
         %{value: 200.0, datetime: ~U[2019-01-02 00:00:00Z], metadata: []}
       ]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        for signal <- signals do
          conn
          |> get_timeseries_signal(signal, slug, from, to, interval, aggregation)
          |> extract_timeseries_data()
        end

      # Assert that all results are lists where we have a map with values
      assert Enum.all?(result, &match?([%{"datetime" => _, "value" => _} | _], &1))
    end)
  end

  test "returns data for all available aggregations", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    # nil means aggregation is not passed, we should not explicitly pass it
    signal = Enum.random(Signal.available_signals())
    {:ok, %{available_aggregations: aggregations}} = Signal.metadata(signal)

    (&Signal.timeseries_data/6)
    |> Sanbase.Mock.prepare_mock2(
      {:ok,
       [
         %{value: 100.0, datetime: ~U[2019-01-01 00:00:00Z], metadata: []},
         %{value: 200.0, datetime: ~U[2019-01-02 00:00:00Z], metadata: []}
       ]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        for aggregation <- aggregations do
          conn
          |> get_timeseries_signal(signal, slug, from, to, interval, aggregation)
          |> extract_timeseries_data()
        end

      # Assert that all results are lists where we have a map with values
      assert Enum.all?(result, &match?([%{"datetime" => _, "value" => _} | _], &1))
    end)
  end

  test "returns error for unavailable aggregations", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    aggregations = Signal.available_aggregations()
    rand_aggregations = Enum.map(1..10, fn _ -> String.to_atom(rand_str()) end)
    rand_aggregations = rand_aggregations -- aggregations
    [signal | _] = Signal.available_signals()

    # Do not mock the `get` function. It will reject the query if the execution
    # reaches it. Currently the execution is halted even earlier because the
    # aggregation is an enum with available values
    result =
      for aggregation <- rand_aggregations do
        get_timeseries_signal(conn, signal, slug, from, to, interval, aggregation)
      end

    # Assert that all results are lists where we have a map with values
    assert Enum.all?(result, &match?(%{"errors" => _}, &1))
  end

  test "returns error for unavailable signals", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    aggregation = :avg
    rand_signals = Enum.map(1..100, fn _ -> rand_str() end)
    rand_signals = rand_signals -- Signal.available_signals()

    # Do not mock the `timeseries_data` function because it's the one that rejects
    for signal <- rand_signals do
      %{"errors" => [%{"message" => error_message}]} =
        get_timeseries_signal(conn, signal, slug, from, to, interval, aggregation)

      assert error_message ==
               "The signal '#{signal}' is not supported, is deprecated or is mistyped."
    end
  end

  # Private functions

  defp get_timeseries_signal(conn, signal, slug, from, to, interval, aggregation) do
    query = get_timeseries_query(signal, slug, from, to, interval, aggregation)

    conn
    |> post("/graphql", query_skeleton(query, "getSignal"))
    |> json_response(200)
  end

  defp extract_timeseries_data(result) do
    %{"data" => %{"getSignal" => %{"timeseriesData" => timeseries_data}}} = result
    timeseries_data
  end

  defp get_timeseries_query(signal, slug, from, to, interval, aggregation) do
    """
      {
        getSignal(signal: "#{signal}"){
          timeseriesData(
            slug: "#{slug}",
            from: "#{from}",
            to: "#{to}",
            interval: "#{interval}",
            aggregation: #{aggregation |> Atom.to_string() |> String.upcase()}){
              datetime
              value
              metadata
            }
        }
      }
    """
  end
end
