defmodule SanbaseWeb.Graphql.Clickhouse.MVRVTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1, from_iso8601!: 1]
  import ExUnit.CaptureLog
  import Sanbase.Factory

  require Sanbase.ClickhouseRepo

  setup do
    project = insert(:project, %{coinmarketcap_id: "ethereum", ticker: "ETH"})

    [
      slug: project.coinmarketcap_id,
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-03T00:00:00Z")
    ]
  end

  test "when requested interval is bigger than values interval", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 0.1],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), 0.2],
             [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), nil]
           ]
         }}
      end do
      response = execute_query(context)
      ratios = parse_response(response)

      assert ratios == [
               %{"ratio" => 0.1, "datetime" => "2019-01-01T00:00:00Z"},
               %{"ratio" => 0.2, "datetime" => "2019-01-02T00:00:00Z"},
               %{"ratio" => nil, "datetime" => "2019-01-03T00:00:00Z"}
             ]
    end
  end

  test "when requested last interval is not full", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 0.0],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), 0.22],
             [from_iso8601_to_unix!("2019-01-03T00:00:00Z"), 0.33],
             [from_iso8601_to_unix!("2019-01-04T00:00:00Z"), 0.44]
           ]
         }}
      end do
      response = execute_query(context, "2d")
      ratios = parse_response(response)

      assert ratios == [
               %{"ratio" => 0.0, "datetime" => "2019-01-01T00:00:00Z"},
               %{"ratio" => 0.22, "datetime" => "2019-01-02T00:00:00Z"},
               %{"ratio" => 0.33, "datetime" => "2019-01-03T00:00:00Z"},
               %{"ratio" => 0.44, "datetime" => "2019-01-04T00:00:00Z"}
             ]
    end
  end

  test "returns empty array when query returns no rows", context do
    with_mock Sanbase.ClickhouseRepo, query: fn _, _ -> {:ok, %{rows: []}} end do
      response = execute_query(context)
      ratios = parse_response(response)

      assert ratios == []
    end
  end

  test "logs warning when query returns error", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ -> {:error, "Some error description here"} end do
      assert capture_log(fn ->
               response = execute_query(context)
               ratios = parse_response(response)
               assert ratios == nil
             end) =~
               ~s/[warn] Can't calculate MVRV ratio for project with coinmarketcap_id: ethereum. Reason: "Some error description here"/
    end
  end

  defp parse_response(response) do
    json_response(response, 200)["data"]["mvrvRatio"]
  end

  defp execute_query(context, interval \\ "1d") do
    query = mvrv_query(context.slug, context.from, context.to, interval)

    context.conn
    |> post("/graphql", query_skeleton(query, "mvrvRatio"))
  end

  defp mvrv_query(slug, from, to, interval) do
    """
      {
        mvrvRatio(slug: "#{slug}", from: "#{from}", to: "#{to}", interval: "#{interval}"){
          datetime,
          ratio
        }
      }
    """
  end
end
