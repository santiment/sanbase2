defmodule Sanbase.Etherbi.TransactionsApiTest do
  use SanbaseWeb.ConnCase, async: false
  @moduletag checkout_repo: [Sanbase.Repo, Sanbase.TimescaleRepo]
  @moduletag timescaledb: true

  require Sanbase.Factory

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.TimescaleFactory

  setup do
    %{user: user} =
      Sanbase.Factory.insert(:subscription_pro_sanbase, user: Sanbase.Factory.insert(:user))

    conn = setup_jwt_auth(build_conn(), user)

    exchange_address = "0x" <> Sanbase.Factory.rand_hex_str()

    project = Sanbase.Factory.insert(:random_erc20_project)
    contract_address = project.main_contract_address

    token_decimals = :math.pow(10, project.token_decimals)

    datetime1 = DateTime.from_naive!(~N[2017-05-13 00:00:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-14 00:00:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-15 00:00:00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-16 00:00:00], "Etc/UTC")
    datetime5 = DateTime.from_naive!(~N[2017-05-17 00:00:00], "Etc/UTC")
    datetime6 = DateTime.from_naive!(~N[2017-05-18 00:00:00], "Etc/UTC")
    datetime7 = DateTime.from_naive!(~N[2017-05-19 00:00:00], "Etc/UTC")
    datetime8 = DateTime.from_naive!(~N[2017-05-20 00:00:00], "Etc/UTC")

    insert(:exchange_funds_flow, %{
      contract_address: contract_address,
      timestamp: datetime1,
      incoming_exchange_funds: 5000 * token_decimals,
      outgoing_exchange_funds: 3000 * token_decimals
    })

    insert(:exchange_funds_flow, %{
      contract_address: contract_address,
      timestamp: datetime2,
      incoming_exchange_funds: 6000 * token_decimals,
      outgoing_exchange_funds: 4000 * token_decimals
    })

    insert(:exchange_funds_flow, %{
      contract_address: contract_address,
      timestamp: datetime3,
      incoming_exchange_funds: 9000 * token_decimals,
      outgoing_exchange_funds: 0
    })

    insert(:exchange_funds_flow, %{
      contract_address: contract_address,
      timestamp: datetime4,
      incoming_exchange_funds: 15_000 * token_decimals,
      outgoing_exchange_funds: 0
    })

    insert(:exchange_funds_flow, %{
      contract_address: contract_address,
      timestamp: datetime5,
      incoming_exchange_funds: 0,
      outgoing_exchange_funds: 18_000 * token_decimals
    })

    insert(:exchange_funds_flow, %{
      contract_address: contract_address,
      timestamp: datetime6,
      incoming_exchange_funds: 1000 * token_decimals,
      outgoing_exchange_funds: 0
    })

    insert(:exchange_funds_flow, %{
      contract_address: contract_address,
      timestamp: datetime7,
      incoming_exchange_funds: 1550 * token_decimals,
      outgoing_exchange_funds: 10_000 * token_decimals
    })

    insert(:exchange_funds_flow, %{
      contract_address: contract_address,
      timestamp: datetime8,
      incoming_exchange_funds: 0,
      outgoing_exchange_funds: 100 * token_decimals
    })

    [
      exchange_address: exchange_address,
      slug: project.coinmarketcap_id,
      from: datetime1,
      to: datetime8,
      conn: conn
    ]
  end

  test "fetch funds flow when no interval is provided", context do
    query = """
    {
      exchangeFundsFlow(
        slug: "#{context.slug}",
        from: "#{context.from}",
        to: "#{context.to}") {
          datetime
          inOutDifference
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "exchangeFundsFlow"))

    funds_flow_list = json_response(result, 200)["data"]["exchangeFundsFlow"]

    assert Enum.find(funds_flow_list, fn %{"inOutDifference" => in_out_difference} ->
             in_out_difference == 2000
           end)
  end

  test "fetch funds flow", context do
    query = """
    {
      exchangeFundsFlow(
        slug: "#{context.slug}",
        from: "#{context.from}",
        to: "#{context.to}",
        interval: "1d") {
          datetime
          inOutDifference
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "exchangeFundsFlow"))

    funds_flow_list = json_response(result, 200)["data"]["exchangeFundsFlow"]

    assert %{"datetime" => "2017-05-13T00:00:00Z", "inOutDifference" => 2.0e3} in funds_flow_list

    assert %{"datetime" => "2017-05-14T00:00:00Z", "inOutDifference" => 2.0e3} in funds_flow_list

    assert %{"datetime" => "2017-05-15T00:00:00Z", "inOutDifference" => 9.0e3} in funds_flow_list

    assert %{"datetime" => "2017-05-16T00:00:00Z", "inOutDifference" => 1.5e4} in funds_flow_list

    assert %{"datetime" => "2017-05-17T00:00:00Z", "inOutDifference" => -1.8e4} in funds_flow_list

    assert %{"datetime" => "2017-05-18T00:00:00Z", "inOutDifference" => 1.0e3} in funds_flow_list

    assert %{"datetime" => "2017-05-19T00:00:00Z", "inOutDifference" => -8450.0} in funds_flow_list

    assert %{"datetime" => "2017-05-20T00:00:00Z", "inOutDifference" => -100.0} in funds_flow_list
  end
end
