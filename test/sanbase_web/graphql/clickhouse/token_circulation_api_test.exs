defmodule Sanbase.Clickhouse.TokenCirculationApiTest do
  use SanbaseWeb.ConnCase, async: false

  require Sanbase.Factory
  import Mock

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory
  import ExUnit.CaptureLog

  setup do
    staked_user = Sanbase.Factory.insert(:staked_user)
    conn = setup_jwt_auth(build_conn(), staked_user)

    slug = "santiment"
    ticker = "SAN"
    insert(:project, %{coinmarketcap_id: slug, ticker: ticker})

    datetime1 = DateTime.from_naive!(~N[2017-05-13 00:00:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-14 00:00:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-15 00:00:00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-16 00:00:00], "Etc/UTC")
    datetime5 = DateTime.from_naive!(~N[2017-05-17 00:00:00], "Etc/UTC")
    datetime6 = DateTime.from_naive!(~N[2017-05-18 00:00:00], "Etc/UTC")
    datetime7 = DateTime.from_naive!(~N[2017-05-19 00:00:00], "Etc/UTC")
    datetime8 = DateTime.from_naive!(~N[2017-05-20 00:00:00], "Etc/UTC")

    [
      slug: slug,
      dt1: datetime1,
      dt2: datetime2,
      dt3: datetime3,
      dt4: datetime4,
      dt5: datetime5,
      dt6: datetime6,
      dt7: datetime7,
      dt8: datetime8,
      conn: conn
    ]
  end

  test "fetch token circulation", context do
    with_mock Sanbase.ClickhouseRepo, [:passthrough],
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [context.dt1 |> DateTime.to_unix(), 5000],
             [context.dt2 |> DateTime.to_unix(), 1000],
             [context.dt3 |> DateTime.to_unix(), 500],
             [context.dt4 |> DateTime.to_unix(), 15_000],
             [context.dt5 |> DateTime.to_unix(), 65_000],
             [context.dt6 |> DateTime.to_unix(), 50],
             [context.dt7 |> DateTime.to_unix(), 5],
             [context.dt8 |> DateTime.to_unix(), 5000]
           ]
         }}
      end do
      query = """
      {
        tokenCirculation(
          slug: "#{context.slug}",
          from: "#{context.dt1}",
          to: "#{context.dt8}",
          interval: "1d") {
            datetime
            tokenCirculation
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "tokenCirculation"))

      token_circulation = json_response(result, 200)["data"]["tokenCirculation"]

      assert %{
               "datetime" => "2017-05-13T00:00:00Z",
               "tokenCirculation" => 5000
             } in token_circulation

      assert %{
               "datetime" => "2017-05-14T00:00:00Z",
               "tokenCirculation" => 1000
             } in token_circulation

      assert %{
               "datetime" => "2017-05-15T00:00:00Z",
               "tokenCirculation" => 500
             } in token_circulation

      assert %{
               "datetime" => "2017-05-16T00:00:00Z",
               "tokenCirculation" => 15000
             } in token_circulation

      assert %{
               "datetime" => "2017-05-17T00:00:00Z",
               "tokenCirculation" => 65000
             } in token_circulation

      assert %{
               "datetime" => "2017-05-18T00:00:00Z",
               "tokenCirculation" => 50
             } in token_circulation

      assert %{
               "datetime" => "2017-05-19T00:00:00Z",
               "tokenCirculation" => 5
             } in token_circulation

      assert %{
               "datetime" => "2017-05-20T00:00:00Z",
               "tokenCirculation" => 5000
             } in token_circulation
    end
  end

  test "fetch token circulation for interval that doesn't consist of full days", context do
    query = """
    {
      tokenCirculation(
        slug: "#{context.slug}",
        from: "#{context.dt1}",
        to: "#{context.dt2}",
        interval: "25h") {
          datetime
          tokenCirculation
      }
    }
    """

    assert capture_log(fn ->
             context.conn
             |> post("/graphql", query_skeleton(query, "tokenCirculation"))
           end) =~ "The interval must consist of whole days"
  end
end
