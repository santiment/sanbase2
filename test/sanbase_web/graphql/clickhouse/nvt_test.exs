defmodule SanbaseWeb.Graphql.Clickhouse.NVTTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]
  import ExUnit.CaptureLog
  import Sanbase.Factory

  alias Sanbase.Clickhouse.NVT

  setup do
    project = insert(:project, %{coinmarketcap_id: "santiment", ticker: "SAN"})

    [
      slug: project.coinmarketcap_id,
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-03T00:00:00Z"),
      interval: "1d"
    ]
  end

  test "returns data from NVT calculation", context do
    with_mock NVT,
      nvt_ratio: fn _, _, _, _ ->
        {:ok,
         [
           %{
             nvt_ratio_circulation: 0.1,
             nvt_ratio_tx_volume: 0.11,
             datetime: from_iso8601!("2019-01-01T00:00:00Z")
           },
           %{
             nvt_ratio_circulation: 0.2,
             nvt_ratio_tx_volume: 0.22,
             datetime: from_iso8601!("2019-01-02T00:00:00Z")
           }
         ]}
      end do
      response = execute_query(context)
      ratios = parse_response(response)

      assert_called(NVT.nvt_ratio(context.slug, context.from, context.to, context.interval))

      assert ratios == [
               %{
                 "nvtRatioCirculation" => 0.1,
                 "nvtRatioTxVolume" => 0.11,
                 "datetime" => "2019-01-01T00:00:00Z"
               },
               %{
                 "nvtRatioCirculation" => 0.2,
                 "nvtRatioTxVolume" => 0.22,
                 "datetime" => "2019-01-02T00:00:00Z"
               }
             ]
    end
  end

  test "returns empty array when there is no data", context do
    with_mock NVT, nvt_ratio: fn _, _, _, _ -> {:ok, []} end do
      response = execute_query(context)
      ratios = parse_response(response)

      assert_called(NVT.nvt_ratio(context.slug, context.from, context.to, context.interval))
      assert ratios == []
    end
  end

  test "logs warning when calculation errors", context do
    error = "Some error description here"

    with_mock NVT,
      nvt_ratio: fn _, _, _, _ -> {:error, error} end do
      assert capture_log(fn ->
               response = execute_query(context)
               ratios = parse_response(response)
               assert ratios == nil
             end) =~
               graphql_error_msg("NVT Ratio", context.slug, error)
    end
  end

  test "uses 1d as default interval", context do
    with_mock NVT, nvt_ratio: fn _, _, _, _ -> {:ok, []} end do
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

      assert_called(NVT.nvt_ratio(context.slug, context.from, context.to, "1d"))
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
