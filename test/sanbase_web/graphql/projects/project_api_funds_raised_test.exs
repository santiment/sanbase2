defmodule SanbaseWeb.Graphql.ProjectApiFundsRaisedTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    # Add the Projects to the Postgres
    insert(:project, %{name: "Test project", slug: "test", ticker: "TEST"})
    insert(:project, %{name: "Bitcoin", slug: "bitcoin", ticker: "BTC"})
    insert(:project, %{name: "Ethereum", slug: "ethereum", ticker: "ETH"})

    datetime1 = ~U[2017-08-19 00:00:00Z]
    datetime2 = ~U[2017-10-17 00:00:00Z]

    # Add the 3 currencies
    currency_eth = insert(:currency, %{code: "ETH"})
    currency_btc = insert(:currency, %{code: "BTC"})
    currency = insert(:currency, %{code: "TEST"})

    # Add a random project and its ICOs
    project = insert(:random_project)

    ico1 = insert(:ico, %{project_id: project.id, end_date: DateTime.to_date(datetime1)})
    insert(:ico_currency, %{ico_id: ico1.id, currency_id: currency_eth.id, amount: 150})
    insert(:ico_currency, %{ico_id: ico1.id, currency_id: currency.id, amount: 50})

    ico2 = insert(:ico, %{project_id: project.id, end_date: DateTime.to_date(datetime2)})
    insert(:ico_currency, %{ico_id: ico2.id, currency_id: currency_btc.id, amount: 200})

    project_no_ico = insert(:random_project)

    [
      datetime: datetime2,
      project: project,
      project_no_ico: project_no_ico
    ]
  end

  test "fetch project funds raised", context do
    %{conn: conn, project: project} = context

    Sanbase.Price
    |> Sanbase.Mock.prepare_mock(:last_record_before, fn slug, datetime ->
      if DateTime.before?(datetime, context.datetime) do
        case slug do
          "bitcoin" -> {:ok, %{price_usd: 2, price_btc: 0.1, marketcap: 100, volume: 100}}
          "test" -> {:ok, %{price_usd: 4, price_btc: 0.05, marketcap: 100, volume: 100}}
          "ethereum" -> {:ok, %{price_usd: 5, price_btc: 0.2, marketcap: nil, volume: nil}}
        end
      else
        case slug do
          "bitcoin" -> {:ok, %{price_usd: 5, price_btc: 0.2, marketcap: 100, volume: 100}}
          "test" -> {:ok, %{price_usd: 4, price_btc: 0.03, marketcap: 100, volume: 100}}
          "ethereum" -> {:ok, %{price_usd: 10, price_btc: 0.8, marketcap: 100, volume: 100}}
        end
      end
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = conn |> get_funds_raised(project) |> get_in(["data", "projectBySlug"])

      assert result == %{
               "name" => project.name,
               "fundsRaisedBtcIcoEndPrice" => 72.5,
               "fundsRaisedEthIcoEndPrice" => 290.0,
               "fundsRaisedUsdIcoEndPrice" => 1950.0,
               "icos" => [
                 %{
                   "endDate" => "2017-08-19",
                   "fundsRaisedBtcIcoEndPrice" => 32.5,
                   "fundsRaisedEthIcoEndPrice" => 190.0,
                   "fundsRaisedUsdIcoEndPrice" => 950.0
                 },
                 %{
                   "endDate" => "2017-10-17",
                   "fundsRaisedEthIcoEndPrice" => 100.0,
                   "fundsRaisedUsdIcoEndPrice" => 1.0e3,
                   "fundsRaisedBtcIcoEndPrice" => 40.0
                 }
               ]
             }
    end)
  end

  test "no ico does not break query", context do
    %{conn: conn, project_no_ico: project} = context

    result =
      conn
      |> get_funds_raised(project)
      |> get_in(["data", "projectBySlug"])

    assert result == %{
             "name" => project.name,
             "fundsRaisedUsdIcoEndPrice" => nil,
             "fundsRaisedEthIcoEndPrice" => nil,
             "fundsRaisedBtcIcoEndPrice" => nil,
             "icos" => []
           }
  end

  # Private functions

  defp get_funds_raised(conn, project) do
    query = """
    {
      projectBySlug(slug: "#{project.slug}") {
        name
        fundsRaisedUsdIcoEndPrice
        fundsRaisedEthIcoEndPrice
        fundsRaisedBtcIcoEndPrice
        icos {
          endDate
          fundsRaisedUsdIcoEndPrice
          fundsRaisedEthIcoEndPrice
          fundsRaisedBtcIcoEndPrice
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "projectBySlug"))
    |> json_response(200)
  end
end
