defmodule SanbaseWeb.Graphql.Clickhouse.ApiAnomalyTimeseriesDataTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Anomaly

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

  test "returns data for an available anomaly", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    aggregation = :avg
    [anomaly | _] = Anomaly.available_anomalies()

    with_mock Anomaly, [:passthrough],
      timeseries_data: fn _, _, _, _, _, _ ->
        {:ok,
         [
           %{value: 100.0, datetime: ~U[2019-01-01 00:00:00Z]},
           %{value: 200.0, datetime: ~U[2019-01-02 00:00:00Z]}
         ]}
      end do
      result =
        get_timeseries_anomaly(conn, anomaly, slug, from, to, interval, aggregation)
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

      assert_called(Anomaly.timeseries_data(anomaly, slug, from, to, interval, aggregation))
    end
  end

  test "returns data for all available anomalies", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    aggregation = :avg
    anomalies = Anomaly.available_anomalies()

    Sanbase.Mock.prepare_mock2(
      &Anomaly.timeseries_data/6,
      {:ok,
       [
         %{value: 100.0, datetime: ~U[2019-01-01 00:00:00Z]},
         %{value: 200.0, datetime: ~U[2019-01-02 00:00:00Z]}
       ]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        for anomaly <- anomalies do
          get_timeseries_anomaly(conn, anomaly, slug, from, to, interval, aggregation)
          |> extract_timeseries_data()
        end

      # Assert that all results are lists where we have a map with values
      assert Enum.all?(result, &match?([%{"datetime" => _, "value" => _} | _], &1))
    end)
  end

  test "returns data for all available aggregations", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    # nil means aggregation is not passed, we should not explicitly pass it
    anomaly = Anomaly.available_anomalies() |> Enum.random()
    {:ok, %{available_aggregations: aggregations}} = Anomaly.metadata(anomaly)

    Sanbase.Mock.prepare_mock2(
      &Anomaly.timeseries_data/6,
      {:ok,
       [
         %{value: 100.0, datetime: ~U[2019-01-01 00:00:00Z]},
         %{value: 200.0, datetime: ~U[2019-01-02 00:00:00Z]}
       ]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        for aggregation <- aggregations do
          get_timeseries_anomaly(conn, anomaly, slug, from, to, interval, aggregation)
          |> extract_timeseries_data()
        end

      # Assert that all results are lists where we have a map with values
      assert Enum.all?(result, &match?([%{"datetime" => _, "value" => _} | _], &1))
    end)
  end

  test "returns error for unavailable aggregations", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    aggregations = Anomaly.available_aggregations()
    rand_aggregations = Enum.map(1..10, fn _ -> rand_str() |> String.to_atom() end)
    rand_aggregations = rand_aggregations -- aggregations
    [anomaly | _] = Anomaly.available_anomalies()

    # Do not mock the `get` function. It will reject the query if the execution
    # reaches it. Currently the execution is halted even earlier because the
    # aggregation is an enum with available values
    result =
      for aggregation <- rand_aggregations do
        get_timeseries_anomaly(conn, anomaly, slug, from, to, interval, aggregation)
      end

    # Assert that all results are lists where we have a map with values
    assert Enum.all?(result, &match?(%{"errors" => _}, &1))
  end

  test "returns error for unavailable anomalies", context do
    %{conn: conn, slug: slug, from: from, to: to, interval: interval} = context
    aggregation = :avg
    rand_anomalies = Enum.map(1..100, fn _ -> rand_str() end)
    rand_anomalies = rand_anomalies -- Anomaly.available_anomalies()

    # Do not mock the `timeseries_data` function because it's the one that rejects
    for anomaly <- rand_anomalies do
      %{"errors" => [%{"message" => error_message}]} =
        get_timeseries_anomaly(conn, anomaly, slug, from, to, interval, aggregation)

      assert error_message == "The anomaly '#{anomaly}' is not supported or is mistyped."
    end
  end

  # Private functions

  defp get_timeseries_anomaly(conn, anomaly, slug, from, to, interval, aggregation) do
    query = get_timeseries_query(anomaly, slug, from, to, interval, aggregation)

    conn
    |> post("/graphql", query_skeleton(query, "getAnomaly"))
    |> json_response(200)
  end

  defp extract_timeseries_data(result) do
    %{"data" => %{"getAnomaly" => %{"timeseriesData" => timeseries_data}}} = result
    timeseries_data
  end

  defp get_timeseries_query(anomaly, slug, from, to, interval, aggregation) do
    """
      {
        getAnomaly(anomaly: "#{anomaly}"){
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
