defmodule SanbaseWeb.Graphql.Clickhouse.ApiSignalTimeseriesDataTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Signal

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

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

    with_mock Signal, [:passthrough],
      timeseries_data: fn _, _, _, _, _, _ ->
        {:ok,
         [
           %{value: 100.0, datetime: ~U[2019-01-01 00:00:00Z]},
           %{value: 200.0, datetime: ~U[2019-01-02 00:00:00Z]}
         ]}
      end do
      result =
        get_timeseries_signal(conn, signal, slug, from, to, interval, aggregation)
        |> extract_timeseries_data()

      assert result == [
               %{
                 "value" => 100.0,
                 "datetime" => "2019-01-01T00:00:00Z"
               },
               %{
                 "value" => 200.0,
                 "datetime" => "2019-01-02T00:00:00Z"
               }
             ]

      assert_called(Signal.timeseries_data(signal, slug, from, to, interval, aggregation))
    end
  end

  test "returns data for all available signals", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    aggregation = :avg
    signals = Signal.available_signals()

    Sanbase.Mock.prepare_mock2(
      &Signal.timeseries_data/6,
      {:ok,
       [
         %{value: 100.0, datetime: ~U[2019-01-01 00:00:00Z]},
         %{value: 200.0, datetime: ~U[2019-01-02 00:00:00Z]}
       ]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        for signal <- signals do
          get_timeseries_signal(conn, signal, slug, from, to, interval, aggregation)
          |> extract_timeseries_data()
        end

      # Assert that all results are lists where we have a map with values
      assert Enum.all?(result, &match?([%{"datetime" => _, "value" => _} | _], &1))
    end)
  end

  test "returns data for all available aggregations", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    # nil means aggregation is not passed, we should not explicitly pass it
    signal = Signal.available_signals() |> Enum.random()
    {:ok, %{available_aggregations: aggregations}} = Signal.metadata(signal)

    Sanbase.Mock.prepare_mock2(
      &Signal.timeseries_data/6,
      {:ok,
       [
         %{value: 100.0, datetime: ~U[2019-01-01 00:00:00Z]},
         %{value: 200.0, datetime: ~U[2019-01-02 00:00:00Z]}
       ]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        for aggregation <- aggregations do
          get_timeseries_signal(conn, signal, slug, from, to, interval, aggregation)
          |> extract_timeseries_data()
        end

      # Assert that all results are lists where we have a map with values
      assert Enum.all?(result, &match?([%{"datetime" => _, "value" => _} | _], &1))
    end)
  end

  test "returns error for unavailable aggregations", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    aggregations = Signal.available_aggregations()
    rand_aggregations = Enum.map(1..10, fn _ -> rand_str() |> String.to_atom() end)
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

      assert error_message == "The signal '#{signal}' is not supported or is mistyped."
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
            aggregation: #{Atom.to_string(aggregation) |> String.upcase()}){
              datetime
              value
            }
        }
      }
    """
  end
end
