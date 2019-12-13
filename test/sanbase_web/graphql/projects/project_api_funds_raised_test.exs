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

    data = [[5, 0.105, 1000, 400]]

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
      project: project,
      project_no_ico: project_no_ico,
      data: data
    ]
  end

  test "fetch project funds raised", context do
    %{conn: conn, project: project, data: data} = context

    expected_result = %{
      "name" => project.name,
      "fundsRaisedUsdIcoEndPrice" => 1200.0,
      "fundsRaisedEthIcoEndPrice" => 250.0,
      "fundsRaisedBtcIcoEndPrice" => 300.0,
      "icos" => [
        %{
          "endDate" => "2017-08-19",
          "fundsRaisedUsdIcoEndPrice" => 200.0,
          "fundsRaisedEthIcoEndPrice" => 150.0,
          "fundsRaisedBtcIcoEndPrice" => 100.0
        },
        %{
          "endDate" => "2017-10-17",
          "fundsRaisedUsdIcoEndPrice" => 1000.0,
          "fundsRaisedEthIcoEndPrice" => 100.0,
          "fundsRaisedBtcIcoEndPrice" => 200.0
        }
      ]
    }

    fn ->
      result = get_funds_raised(conn, project) |> get_in(["data", "projectBySlug"])

      assert result == expected_result
    end
    |> Sanbase.Mock.with_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: data}})
  end

  test "no ico does not break query", context do
    %{conn: conn, project_no_ico: project} = context

    result =
      get_funds_raised(conn, project)
      |> get_in(["data", "projectBySlug"])

    expected_result = %{
      "name" => project.name,
      "fundsRaisedUsdIcoEndPrice" => nil,
      "fundsRaisedEthIcoEndPrice" => nil,
      "fundsRaisedBtcIcoEndPrice" => nil,
      "icos" => []
    }

    assert result == expected_result
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
