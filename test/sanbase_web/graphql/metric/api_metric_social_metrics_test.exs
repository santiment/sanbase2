defmodule SanbaseWeb.Graphql.ApiMetricSocialMetricsTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    [
      conn: conn,
      project: insert(:random_erc20_project),
      from: ~U[2019-01-01T00:00:00Z],
      to: ~U[2019-01-02T00:00:00Z],
      after_to: ~U[2019-01-03T00:00:00Z],
      interval: "1d"
    ]
  end

  describe "metrics by slug selector" do
    test "community messages - one source returns more data", context do
      %{conn: conn, project: project, from: from, to: to, interval: interval, after_to: after_to} =
        context

      [_, combined_metrics] = community_messages_count_metrics()

      resp1 = """
       [
        {"mentions_count": 100, "timestamp": #{DateTime.to_unix(from)}},
        {"mentions_count": 200, "timestamp": #{DateTime.to_unix(to)}},
        {"mentions_count": 300, "timestamp": #{DateTime.to_unix(after_to)}}
      ]
      """

      resp2 = """
      [
        {"mentions_count": 100, "timestamp": #{DateTime.to_unix(from)}},
        {"mentions_count": 200, "timestamp": #{DateTime.to_unix(to)}}
      ]
      """

      HTTPoison
      |> Sanbase.Mock.prepare_mock(:get, fn url, _, _ ->
        if String.contains?(url, "telegram") do
          {:ok, %HTTPoison.Response{body: resp1, status_code: 200}}
        else
          {:ok, %HTTPoison.Response{body: resp2, status_code: 200}}
        end
      end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        for metric <- combined_metrics do
          result =
            conn
            |> get_timeseries_metric(metric, :slug, project.slug, from, to, interval)
            |> extract_timeseries_data()

          # There is only 1 source for community messages - telegram
          assert result == [
                   %{"value" => 100.0, "datetime" => DateTime.to_iso8601(from)},
                   %{"value" => 200.0, "datetime" => DateTime.to_iso8601(to)},
                   %{"value" => 300.0, "datetime" => DateTime.to_iso8601(after_to)}
                 ]
        end
      end)
    end

    test "community messages count test", context do
      %{conn: conn, project: project, from: from, to: to, interval: interval} = context
      [single_source_metrics, combined_metrics] = community_messages_count_metrics()

      resp = """
      [
        {"mentions_count": 100, "timestamp": #{DateTime.to_unix(from)}},
        {"mentions_count": 200, "timestamp": #{DateTime.to_unix(to)}}
      ]
      """

      (&HTTPoison.get/3)
      |> Sanbase.Mock.prepare_mock2({:ok, %HTTPoison.Response{body: resp, status_code: 200}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        for metric <- single_source_metrics do
          result =
            conn
            |> get_timeseries_metric(metric, :slug, project.slug, from, to, interval)
            |> extract_timeseries_data()

          assert result == [
                   %{"value" => 100.0, "datetime" => DateTime.to_iso8601(from)},
                   %{"value" => 200.0, "datetime" => DateTime.to_iso8601(to)}
                 ]
        end

        for metric <- combined_metrics do
          result =
            conn
            |> get_timeseries_metric(metric, :slug, project.slug, from, to, interval)
            |> extract_timeseries_data()

          # There is only 1 source for community messages
          assert result == [
                   %{"value" => 100.0, "datetime" => DateTime.to_iso8601(from)},
                   %{"value" => 200.0, "datetime" => DateTime.to_iso8601(to)}
                 ]
        end
      end)
    end

    test "social volume test", context do
      %{conn: conn, project: project, from: from, to: to, interval: interval} = context
      metrics = social_volume_metrics()

      resp = """
      {"data":{"#{from}":100,"#{to}":200}}
      """

      res = {:ok, [%{datetime: from, value: 100.0}, %{datetime: to, value: 200.0}]}

      (&HTTPoison.get/3)
      |> Sanbase.Mock.prepare_mock2({:ok, %HTTPoison.Response{body: resp, status_code: 200}})
      |> Sanbase.Mock.prepare_mock2(&Sanbase.Clickhouse.MetricAdapter.timeseries_data/6, res)
      |> Sanbase.Mock.run_with_mocks(fn ->
        for metric <- metrics do
          result =
            conn
            |> get_timeseries_metric(metric, :slug, project.slug, from, to, interval)
            |> extract_timeseries_data()

          assert result == [
                   %{"value" => 100.0, "datetime" => DateTime.to_iso8601(from)},
                   %{"value" => 200.0, "datetime" => DateTime.to_iso8601(to)}
                 ]
        end
      end)
    end

    test "social dominance test", context do
      %{conn: conn, project: project, from: from, to: to, interval: interval} = context
      metrics = social_dominance_metrics()

      resp = """
      {"data":{"#{from}":15,"#{to}":20}}
      """

      res = {:ok, [%{datetime: from, value: 15.0}, %{datetime: to, value: 20.0}]}

      (&HTTPoison.get/3)
      |> Sanbase.Mock.prepare_mock2({:ok, %HTTPoison.Response{body: resp, status_code: 200}})
      |> Sanbase.Mock.prepare_mock2(&Sanbase.Clickhouse.MetricAdapter.timeseries_data/6, res)
      |> Sanbase.Mock.run_with_mocks(fn ->
        for metric <- metrics do
          result =
            conn
            |> get_timeseries_metric(metric, :slug, project.slug, from, to, interval)
            |> extract_timeseries_data()

          assert result == [
                   %{"value" => 15.0, "datetime" => DateTime.to_iso8601(from)},
                   %{"value" => 20.0, "datetime" => DateTime.to_iso8601(to)}
                 ]
        end
      end)
    end
  end

  describe "metrics by text selector" do
    test "social volume test", context do
      %{conn: conn, from: from, to: to, interval: interval} = context
      metrics = social_volume_metrics()

      resp = """
      {"data":{"#{from}":12,"#{to}":18}}
      """

      (&HTTPoison.get/3)
      |> Sanbase.Mock.prepare_mock2({:ok, %HTTPoison.Response{body: resp, status_code: 200}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        for metric <- metrics do
          result =
            conn
            |> get_timeseries_metric(metric, :text, "buy OR sell", from, to, interval)
            |> extract_timeseries_data()

          assert result == [
                   %{"value" => 12.0, "datetime" => DateTime.to_iso8601(from)},
                   %{"value" => 18.0, "datetime" => DateTime.to_iso8601(to)}
                 ]
        end
      end)
    end

    test "social_volume - one source returns more data", context do
      %{conn: conn, from: from, to: to, interval: interval, after_to: after_to} = context
      metrics = social_volume_metrics()

      resp1 = """
      {"data":{"#{from}":12,"#{to}":18,"#{after_to}":10}}
      """

      resp2 = """
      {"data":{"#{from}":12,"#{to}":18}}
      """

      HTTPoison
      |> Sanbase.Mock.prepare_mock(:get, fn _, _, options ->
        source =
          options
          |> Keyword.get(:params)
          |> Enum.find(&match?({"source", _}, &1))
          |> elem(1)
          |> to_string()

        case source do
          "telegram" -> {:ok, %HTTPoison.Response{body: resp1, status_code: 200}}
          _ -> {:ok, %HTTPoison.Response{body: resp2, status_code: 200}}
        end
      end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        for metric <- metrics do
          result =
            conn
            |> get_timeseries_metric(metric, :text, "12k OR 14k", from, to, interval)
            |> extract_timeseries_data()

          case metric do
            "social_volume_telegram" ->
              assert result == [
                       %{"value" => 12.0, "datetime" => DateTime.to_iso8601(from)},
                       %{"value" => 18.0, "datetime" => DateTime.to_iso8601(to)},
                       %{"value" => 10.0, "datetime" => DateTime.to_iso8601(after_to)}
                     ]

            _ ->
              assert result == [
                       %{"value" => 12.0, "datetime" => DateTime.to_iso8601(from)},
                       %{"value" => 18.0, "datetime" => DateTime.to_iso8601(to)}
                     ]
          end
        end
      end)
    end

    test "social dominance test", context do
      %{conn: conn, from: from, to: to, interval: interval} = context

      metrics = social_dominance_metrics()

      text_mentions = [
        %{mentions_count: 48, datetime: from},
        %{mentions_count: 72, datetime: to}
      ]

      total_mentions = [
        %{mentions_count: 2210, datetime: from},
        %{mentions_count: 1203, datetime: to}
      ]

      Sanbase.SocialData.SocialVolume
      |> Sanbase.Mock.prepare_mock(:social_volume, fn
        %{text: text}, _, _, _, _ ->
          case text do
            "*" -> {:ok, total_mentions}
            _ -> {:ok, text_mentions}
          end
      end)
      |> Sanbase.Mock.run_with_mocks(fn ->
        for metric <- metrics do
          result =
            conn
            |> get_timeseries_metric(metric, :text, "text", from, to, interval)
            |> extract_timeseries_data()

          assert result == [
                   %{"value" => 2.17, "datetime" => DateTime.to_iso8601(from)},
                   %{"value" => 5.99, "datetime" => DateTime.to_iso8601(to)}
                 ]
        end
      end)
    end
  end

  describe "metrics by source selector" do
    test "social active users test with success response", context do
      %{conn: conn, from: from, to: to, interval: interval} = context

      resp = """
      {"data":{"#{from}":12,"#{to}":18}}
      """

      (&HTTPoison.get/3)
      |> Sanbase.Mock.prepare_mock2({:ok, %HTTPoison.Response{body: resp, status_code: 200}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          conn
          |> get_timeseries_metric(
            "social_active_users",
            :source,
            "telegram",
            from,
            to,
            interval
          )
          |> extract_timeseries_data()

        assert result == [
                 %{"value" => 12.0, "datetime" => DateTime.to_iso8601(from)},
                 %{"value" => 18.0, "datetime" => DateTime.to_iso8601(to)}
               ]
      end)
    end

    test "social active users test with empty response", context do
      %{conn: conn, from: from, to: to, interval: interval} = context

      resp = """
      {"data":{}}
      """

      (&HTTPoison.get/3)
      |> Sanbase.Mock.prepare_mock2({:ok, %HTTPoison.Response{body: resp, status_code: 200}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          conn
          |> get_timeseries_metric(
            "social_active_users",
            :source,
            "telegram",
            from,
            to,
            interval
          )
          |> extract_timeseries_data()

        assert result == []
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

  defp community_messages_count_metrics do
    Sanbase.SocialData.MetricAdapter.available_metrics()
    |> Enum.filter(fn
      "community_messages_count" <> _ -> true
      _ -> false
    end)
    |> split_single_combined()
  end

  defp social_volume_metrics do
    Enum.filter(Sanbase.SocialData.MetricAdapter.available_metrics(), fn
      "social_volume" <> _ -> true
      _ -> false
    end)
  end

  defp social_dominance_metrics do
    Enum.filter(Sanbase.SocialData.MetricAdapter.available_metrics(), fn
      "social_dominance" <> _ -> true
      _ -> false
    end)
  end

  defp split_single_combined(metrics) do
    map =
      Enum.group_by(metrics, fn metric ->
        if String.contains?(metric, "total") do
          :combined
        else
          :single
        end
      end)

    [Map.get(map, :single), Map.get(map, :combined)]
  end
end
