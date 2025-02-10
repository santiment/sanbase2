defmodule SanbaseWeb.Graphql.ApiMetricMetadataTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Metric

  test "returns data for availableFounders", %{conn: conn} do
    metrics_with_founders =
      Enum.filter(Metric.available_metrics(), fn m ->
        {:ok, selectors} = Metric.available_selectors(m)

        :founders in selectors
      end)

    insert(:project, %{name: "Ethereum", ticker: "ETH", slug: "ethereum"})
    insert(:project, %{name: "Bitcoin", ticker: "BTC", slug: "bitcoin"})

    rows = [
      ["Vitalik Buterin", "ethereum"],
      ["Satoshi Nakamoto", "bitcoin"]
    ]

    query = fn metric ->
      """
      {
        getMetric(metric: "#{metric}"){
          metadata{
            availableFounders{ name project{ name } }
          }
        }
      }
      """
    end

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      for metric <- metrics_with_founders do
        result =
          conn
          |> post("/graphql", query_skeleton(query.(metric)))
          |> json_response(200)
          |> get_in(["data", "getMetric", "metadata", "availableFounders"])

        assert length(result) == 2
        assert %{"name" => "Satoshi Nakamoto", "project" => %{"name" => "Bitcoin"}} in result
        assert %{"name" => "Vitalik Buterin", "project" => %{"name" => "Ethereum"}} in result
      end
    end)

    result =
      conn
      |> post("/graphql", query_skeleton(query.("price_usd")))
      |> json_response(200)
      |> get_in(["data", "getMetric", "metadata", "availableFounders"])

    # No founders for metrics without founders in their selectors
    assert result == []
  end

  test "returns data for availableFounders with slug filter", %{conn: conn} do
    metric_with_founders =
      Metric.available_metrics()
      |> Enum.filter(fn m ->
        {:ok, selectors} = Metric.available_selectors(m)

        :founders in selectors
      end)
      |> hd()

    insert(:project, %{name: "Ethereum", ticker: "ETH", slug: "ethereum"})
    insert(:project, %{name: "Bitcoin", ticker: "BTC", slug: "bitcoin"})

    rows = [
      ["Satoshi Nakamoto", "bitcoin"]
    ]

    query =
      """
      {
        getMetric(metric: "#{metric_with_founders}"){
          metadata{
            availableFounders(slug: "bitcoin"){ name project{ name } }
          }
        }
      }
      """

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        conn
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)
        |> get_in(["data", "getMetric", "metadata", "availableFounders"])

      assert length(result) == 1
      assert %{"name" => "Satoshi Nakamoto", "project" => %{"name" => "Bitcoin"}} in result
    end)
  end

  test "returns data for all available metric", %{conn: conn} do
    metrics = Enum.shuffle(Metric.available_metrics())

    aggregations = Metric.available_aggregations()

    aggregations =
      Enum.map(aggregations, fn aggr -> aggr |> Atom.to_string() |> String.upcase() end)

    for metric <- metrics do
      %{"data" => %{"getMetric" => %{"metadata" => metadata}}} = get_metric_metadata(conn, metric)

      assert metadata["metric"] == metric

      assert match?(
               %{
                 "metric" => _,
                 "defaultAggregation" => _,
                 "minInterval" => _,
                 "dataType" => _
               },
               metadata
             )

      assert is_binary(metadata["humanReadableName"])
      assert metadata["defaultAggregation"] in aggregations

      assert metadata["minInterval"] in [
               "1s",
               "1m",
               "5m",
               "15m",
               "1h",
               "6h",
               "8h",
               "1d",
               "7d"
             ]

      assert metadata["dataType"] in ["TIMESERIES", "HISTOGRAM", "TABLE"]
      assert metadata["isRestricted"] in [true, false]

      assert Enum.all?(
               metadata["availableSelectors"],
               &(&1 in [
                   "ADDRESS",
                   "BLOCKCHAIN_ADDRESS",
                   "BLOCKCHAIN",
                   "CONTRACT_ADDRESS",
                   "ECOSYSTEM",
                   "FOUNDERS",
                   "HOLDERS_COUNT",
                   "LABEL_FQN",
                   "LABEL_FQNS",
                   "LABEL",
                   "MARKET_SEGMENTS",
                   "OWNER",
                   "SLUG",
                   "SLUGS",
                   "SOURCE",
                   "TEXT",
                   "TOKEN_ID"
                 ])
             )

      assert Enum.all?(
               metadata["availableAggregations"],
               &Enum.member?(aggregations, &1)
             )

      assert is_nil(metadata["restrictedFrom"]) or
               match?(
                 %DateTime{},
                 Sanbase.DateTimeUtils.from_iso8601!(metadata["restrictedFrom"])
               )

      assert is_nil(metadata["restrictedTo"]) or
               match?(
                 %DateTime{},
                 Sanbase.DateTimeUtils.from_iso8601!(metadata["restrictedTo"])
               )
    end
  end

  test "returns error for unavailable metric", %{conn: conn} do
    rand_metrics = Enum.map(1..20, fn _ -> rand_str() end)
    rand_metrics = rand_metrics -- Metric.available_metrics()

    # Do not mock the `histogram_data` function because it's the one that rejects
    for metric <- rand_metrics do
      %{
        "errors" => [
          %{"message" => error_message}
        ]
      } = get_metric_metadata(conn, metric)

      assert error_message ==
               "The metric '#{metric}' is not supported, is deprecated or is mistyped."
    end
  end

  test "get internal_metric for clickhouse metrics", %{conn: conn} do
    internal_metric =
      conn
      |> get_metric_metadata("age_consumed")
      |> get_in(["data", "getMetric", "metadata", "internalMetric"])

    assert internal_metric == "stack_age_consumed_5min"

    internal_metric =
      conn
      |> get_metric_metadata("dev_activity_1d")
      |> get_in(["data", "getMetric", "metadata", "internalMetric"])

    assert internal_metric == "dev_activity"

    internal_metric =
      conn
      |> get_metric_metadata("daily_active_addresses")
      |> get_in(["data", "getMetric", "metadata", "internalMetric"])

    assert internal_metric == "daily_active_addresses"
  end

  defp get_metric_metadata(conn, metric) do
    query = """
    {
      getMetric(metric: "#{metric}"){
        metadata{
          minInterval
          defaultAggregation
          availableAggregations
          availableSelectors
          dataType
          metric
          internalMetric
          humanReadableName
          isTimebound
          isRestricted
          restrictedFrom
          restrictedTo
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
