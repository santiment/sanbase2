defmodule SanbaseWeb.Graphql.ApiMetricTimeseriesDataTransformTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]

  alias Sanbase.Metric

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    [conn: conn, slug: "ethereum"]
  end

  test "moving average transform", context do
    %{conn: conn, slug: slug} = context
    [metric | _] = Metric.available_timeseries_metrics()

    with_mock Metric, [:passthrough],
      timeseries_data: fn _, _, _, _, _, _ ->
        {:ok,
         [
           %{datetime: ~U[2019-01-01T00:00:00Z], value: 100.0},
           %{datetime: ~U[2019-01-02T00:00:00Z], value: 200.0},
           %{datetime: ~U[2019-01-03T00:00:00Z], value: 50.0},
           %{datetime: ~U[2019-01-04T00:00:00Z], value: 400.0},
           %{datetime: ~U[2019-01-05T00:00:00Z], value: 300.0},
           %{datetime: ~U[2019-01-06T00:00:00Z], value: 10.0},
           %{datetime: ~U[2019-01-07T00:00:00Z], value: 200.0},
           %{datetime: ~U[2019-01-08T00:00:00Z], value: 320.0}
         ]}
      end do
      result =
        get_timeseries_metric(
          conn,
          metric,
          slug,
          ~U[2019-01-04T00:00:00Z],
          ~U[2019-01-08T00:00:00Z],
          "1d",
          :avg,
          %{type: "moving_average", moving_average_base: 3}
        )
        |> extract_timeseries_data()

      assert result == [
               %{"datetime" => "2019-01-04T00:00:00Z", "value" => 216.67},
               %{"datetime" => "2019-01-05T00:00:00Z", "value" => 250.0},
               %{"datetime" => "2019-01-06T00:00:00Z", "value" => 236.67},
               %{"datetime" => "2019-01-07T00:00:00Z", "value" => 170.0},
               %{"datetime" => "2019-01-08T00:00:00Z", "value" => 176.67}
             ]

      assert_called(
        Metric.timeseries_data(
          metric,
          %{slug: slug},
          ~U[2019-01-01T00:00:00Z],
          ~U[2019-01-08T00:00:00Z],
          "1d",
          :avg
        )
      )
    end
  end

  # Private functions

  defp get_timeseries_metric(conn, metric, slug, from, to, interval, aggregation, transform) do
    query = get_timeseries_query(metric, slug, from, to, interval, aggregation, transform)

    conn
    |> post("/graphql", query_skeleton(query, "getMetric"))
    |> json_response(200)
  end

  defp extract_timeseries_data(result) do
    %{"data" => %{"getMetric" => %{"timeseriesData" => timeseries_data}}} = result
    timeseries_data
  end

  defp get_timeseries_query(metric, slug, from, to, interval, aggregation, transform) do
    transform_text =
      Enum.map(transform, fn {key, value} -> "#{key}: #{inspect(value)}" end)
      |> Enum.join(", ")

    """
      {
        getMetric(metric: "#{metric}"){
          timeseriesData(
            slug: "#{slug}"
            from: "#{from}"
            to: "#{to}"
            interval: "#{interval}"
            aggregation: #{Atom.to_string(aggregation) |> String.upcase()}
            transform: {#{transform_text}}
            ){
              datetime
              value
            }
        }
      }
    """
  end
end
