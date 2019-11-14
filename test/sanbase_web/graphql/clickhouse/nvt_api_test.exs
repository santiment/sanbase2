defmodule SanbaseWeb.Graphql.NVTApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.TestHelpers
  import ExUnit.CaptureLog
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)
    datetimes = generate_datetimes(~U[2019-01-01 00:00:00Z], "1d", 3)

    project = insert(:project, %{slug: "santiment", ticker: "SAN"})

    %{
      conn: conn,
      slug: project.slug,
      from: List.first(datetimes),
      to: List.last(datetimes),
      datetimes: datetimes,
      interval: "1d"
    }
  end

  test "returns data from NVT calculation", context do
    %{datetimes: datetimes} = context

    with_mocks([
      {Sanbase.Metric, [:passthrough],
       [
         first_datetime: fn _, _ -> {:ok, context.from} end,
         timeseries_data: fn
           "nvt_transaction_volume", _, _, _, _, _ ->
             {:ok,
              [
                %{datetime: Enum.at(datetimes, 0), value: 100},
                %{datetime: Enum.at(datetimes, 1), value: 200},
                %{datetime: Enum.at(datetimes, 2), value: 300}
              ]}

           "nvt", _, _, _, _, _ ->
             {:ok,
              [
                %{datetime: Enum.at(datetimes, 0), value: 50},
                %{datetime: Enum.at(datetimes, 1), value: 70},
                %{datetime: Enum.at(datetimes, 2), value: 30}
              ]}
         end
       ]}
    ]) do
      response = execute_query(context)

      ratios = parse_response(response)

      assert ratios == [
               %{
                 "nvtRatioCirculation" => 50,
                 "nvtRatioTxVolume" => 100,
                 "datetime" => DateTime.to_iso8601(Enum.at(datetimes, 0))
               },
               %{
                 "nvtRatioCirculation" => 70,
                 "nvtRatioTxVolume" => 200,
                 "datetime" => DateTime.to_iso8601(Enum.at(datetimes, 1))
               },
               %{
                 "nvtRatioCirculation" => 30,
                 "nvtRatioTxVolume" => 300,
                 "datetime" => DateTime.to_iso8601(Enum.at(datetimes, 2))
               }
             ]
    end
  end

  test "returns empty array when there is no data", context do
    with_mocks([
      {Sanbase.Metric, [:passthrough],
       [
         first_datetime: fn _, _ -> {:ok, context.from} end,
         timeseries_data: fn _, _, _, _, _, _ -> {:ok, []} end
       ]}
    ]) do
      response = execute_query(context)
      ratios = parse_response(response)

      assert ratios == []
    end
  end

  test "returns error to the user when calculation errors", context do
    error = "Some error description here"

    with_mock Sanbase.Metric,
      timeseries_data: fn _, _, _, _, _, _ -> {:error, error} end do
      log =
        capture_log(fn ->
          response = execute_query(context)
          ratios = parse_response(response)
          assert ratios == nil
        end)

      assert log =~ "Can't fetch nvt"
      assert log =~ "Some error description here"
    end
  end

  test "uses 1d as default interval", context do
    with_mock Sanbase.Metric, timeseries_data: fn _, _, _, _, _, _ -> {:ok, []} end do
      query = """
        {
          nvtRatio(slug: "#{context.slug}", from: "#{context.from}", to: "#{context.to}"){
            datetime,
            nvtRatioCirculation,
            nvtRatioTxVolume
          }
        }
      """

      context.conn
      |> post("/graphql", query_skeleton(query, "nvtRatio"))

      assert_called(Sanbase.Metric.timeseries_data(:_, :_, context.from, context.to, "1d", :_))
    end
  end

  defp parse_response(response) do
    json_response(response, 200)["data"]["nvtRatio"]
  end

  defp execute_query(context) do
    query = nvt_query(context.slug, context.from, context.to, context.interval)

    context.conn
    |> post("/graphql", query_skeleton(query, "nvtRatio"))
  end

  defp nvt_query(slug, from, to, interval) do
    """
      {
        nvtRatio(slug: "#{slug}", from: "#{from}", to: "#{to}", interval: "#{interval}"){
          datetime,
          nvtRatioCirculation,
          nvtRatioTxVolume
        }
      }
    """
  end
end
