defmodule SanbaseWeb.Graphql.ApiMetricSocialMetricsTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    [
      conn: conn,
      project: insert(:random_erc20_project),
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-02T00:00:00Z"),
      interval: "1d"
    ]
  end

  describe "metrics by slug selector" do
    test "community messages count test", context do
      %{conn: conn, project: project, from: from, to: to, interval: interval} = context
      [single_source_metrics, combined_metrics] = community_messages_count_metrics()

      resp = """
      [
        {"mentions_count": 100, "timestamp": #{DateTime.to_unix(from)}},
        {"mentions_count": 200, "timestamp": #{DateTime.to_unix(to)}}
      ]
      """

      Sanbase.Mock.prepare_mock2(
        &HTTPoison.get/3,
        {:ok, %HTTPoison.Response{body: resp, status_code: 200}}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        for metric <- single_source_metrics do
          result =
            get_timeseries_metric(conn, metric, :slug, project.slug, from, to, interval)
            |> extract_timeseries_data()

          assert result == [
                   %{"value" => 100.0, "datetime" => from |> DateTime.to_iso8601()},
                   %{"value" => 200.0, "datetime" => to |> DateTime.to_iso8601()}
                 ]
        end

        for metric <- combined_metrics do
          result =
            get_timeseries_metric(conn, metric, :slug, project.slug, from, to, interval)
            |> extract_timeseries_data()

          # There is only 1 source for community messages
          assert result == [
                   %{"value" => 100.0, "datetime" => from |> DateTime.to_iso8601()},
                   %{"value" => 200.0, "datetime" => to |> DateTime.to_iso8601()}
                 ]
        end
      end)
    end

    test "social volume test", context do
      %{conn: conn, project: project, from: from, to: to, interval: interval} = context
      [single_source_metrics, combined_metrics] = social_volume_metrics()

      resp = """
      [
        {"mentions_count": 100, "timestamp": #{DateTime.to_unix(from)}},
        {"mentions_count": 200, "timestamp": #{DateTime.to_unix(to)}}
      ]
      """

      Sanbase.Mock.prepare_mock2(
        &HTTPoison.get/3,
        {:ok, %HTTPoison.Response{body: resp, status_code: 200}}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        for metric <- single_source_metrics do
          result =
            get_timeseries_metric(conn, metric, :slug, project.slug, from, to, interval)
            |> extract_timeseries_data()

          assert result == [
                   %{"value" => 100.0, "datetime" => from |> DateTime.to_iso8601()},
                   %{"value" => 200.0, "datetime" => to |> DateTime.to_iso8601()}
                 ]
        end

        for metric <- combined_metrics do
          result =
            get_timeseries_metric(conn, metric, :slug, project.slug, from, to, interval)
            |> extract_timeseries_data()

          assert result == [
                   %{"value" => 400.0, "datetime" => from |> DateTime.to_iso8601()},
                   %{"value" => 800.0, "datetime" => to |> DateTime.to_iso8601()}
                 ]
        end
      end)
    end

    test "social dominance test", context do
      %{conn: conn, project: project, from: from, to: to, interval: interval} = context
      [single_source_metrics, combined_metrics] = social_dominance_metrics()
      ticker_slug = "#{project.ticker}_#{project.slug}"

      resp = """
      [
        {"#{ticker_slug}": 10, "ETH_ethereum": 12, "BTC_bitcoin": 102, "datetime": #{
        DateTime.to_unix(from)
      }},
        {"#{ticker_slug}": 20, "ETH_ethereum": 12, "BTC_bitcoin": 102, "datetime": #{
        DateTime.to_unix(to)
      }}
      ]
      """

      Sanbase.Mock.prepare_mock2(
        &HTTPoison.get/3,
        {:ok, %HTTPoison.Response{body: resp, status_code: 200}}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        for metric <- single_source_metrics do
          result =
            get_timeseries_metric(conn, metric, :slug, project.slug, from, to, interval)
            |> extract_timeseries_data()

          assert result == [
                   %{"value" => 8.06, "datetime" => from |> DateTime.to_iso8601()},
                   %{"value" => 14.93, "datetime" => to |> DateTime.to_iso8601()}
                 ]
        end

        for metric <- combined_metrics do
          result =
            get_timeseries_metric(conn, metric, :slug, project.slug, from, to, interval)
            |> extract_timeseries_data()

          assert result == [
                   %{"value" => 8.06, "datetime" => from |> DateTime.to_iso8601()},
                   %{"value" => 14.93, "datetime" => to |> DateTime.to_iso8601()}
                 ]
        end
      end)
    end
  end

  describe "metrics by text selector" do
    test "social volume test", context do
      %{conn: conn, from: from, to: to, interval: interval} = context
      [single_source_metrics, combined_metrics] = social_volume_metrics()

      resp = """
      {
        "messages":
          [
            {"text": "BTC moon", "timestamp": #{DateTime.to_unix(from)}},
            {"text": "12k whoo btc?", "timestamp": #{DateTime.to_unix(to)}}
          ],
        "chart_data":
          [
            {"mentions_count": 12, "timestamp": #{DateTime.to_unix(from)}},
            {"mentions_count": 18, "timestamp": #{DateTime.to_unix(to)}}
          ]
      }
      """

      Sanbase.Mock.prepare_mock2(
        &HTTPoison.get/3,
        {:ok, %HTTPoison.Response{body: resp, status_code: 200}}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        for metric <- single_source_metrics do
          result =
            get_timeseries_metric(conn, metric, :text, "buy OR sell", from, to, interval)
            |> extract_timeseries_data()

          assert result == [
                   %{"value" => 12.0, "datetime" => from |> DateTime.to_iso8601()},
                   %{"value" => 18.0, "datetime" => to |> DateTime.to_iso8601()}
                 ]
        end

        for metric <- combined_metrics do
          result =
            get_timeseries_metric(conn, metric, :text, "12k OR 14k", from, to, interval)
            |> extract_timeseries_data()

          assert result == [
                   %{"value" => 48.0, "datetime" => from |> DateTime.to_iso8601()},
                   %{"value" => 72.0, "datetime" => to |> DateTime.to_iso8601()}
                 ]
        end
      end)
    end
  end

  # Private functions

  defp get_timeseries_metric(conn, metric, selector_key, selector_value, from, to, interval) do
    query = get_timeseries_query(metric, selector_key, selector_value, from, to, interval)

    conn
    |> post("/graphql", query_skeleton(query, "getMetric"))
    |> json_response(200)
  end

  defp extract_timeseries_data(result) do
    %{"data" => %{"getMetric" => %{"timeseriesData" => timeseries_data}}} = result
    timeseries_data
  end

  defp get_timeseries_query(metric, selector_key, selector_value, from, to, interval) do
    """
      {
        getMetric(metric: "#{metric}"){
          timeseriesData(
            selector: {#{selector_key}: "#{selector_value}"}
            from: "#{from}"
            to: "#{to}"
            interval: "#{interval}"){
              datetime
              value
            }
        }
      }
    """
  end

  defp community_messages_count_metrics() do
    Sanbase.Metric.available_metrics()
    |> Enum.filter(fn
      "community_messages_count" <> _ -> true
      _ -> false
    end)
    |> split_single_combined()
  end

  defp social_volume_metrics() do
    Sanbase.Metric.available_metrics()
    |> Enum.filter(fn
      "social_volume" <> _ -> true
      _ -> false
    end)
    |> split_single_combined()
  end

  defp social_dominance_metrics() do
    Sanbase.Metric.available_metrics()
    |> Enum.filter(fn
      "social_dominance" <> _ -> true
      _ -> false
    end)
    |> split_single_combined()
  end

  defp split_single_combined(metrics) do
    map =
      Enum.group_by(metrics, fn metric ->
        case String.contains?(metric, "total") do
          false -> :single
          true -> :combined
        end
      end)

    [Map.get(map, :single), Map.get(map, :combined)]
  end
end
