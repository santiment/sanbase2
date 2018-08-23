defmodule SanbaseWeb.Graphql.MarketSegmentResolverTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Repo
  alias Sanbase.Model.{Project, MarketSegment, Infrastructure}
  alias Sanbase.Auth.User

  setup do
    user =
      %User{salt: User.generate_salt(), privacy_policy_accepted: true}
      |> Repo.insert!()

    contract_address = "0x123123123"

    eth_infrastructure =
      %Infrastructure{code: "ETH"}
      |> Repo.insert!()

    btc_infrastructure =
      %Infrastructure{code: "BTC"}
      |> Repo.insert!()

    # All necesarry fields
    %MarketSegment{
      name: "Foo",
      projects: [
        %Project{
          name: "Foo Project",
          coinmarketcap_id: "fooproject",
          main_contract_address: contract_address,
          infrastructure_id: eth_infrastructure.id
        }
      ]
    }
    |> Repo.insert!()

    # Missing coinmarketcap_id - won't appear in erc20 and currency market segments
    %MarketSegment{
      name: "Bar",
      projects: [
        %Project{
          name: "Bar Project",
          main_contract_address: contract_address,
          infrastructure_id: eth_infrastructure.id
        }
      ]
    }
    |> Repo.insert!()

    # Missing main_contract_address - won't appear in erc20 market segments
    %MarketSegment{
      name: "Baz",
      projects: [
        %Project{
          name: "Baz Project",
          coinmarketcap_id: "bazproject",
          infrastructure_id: eth_infrastructure.id
        }
      ]
    }
    |> Repo.insert!()

    # Infrastructure is not "ETH" - won't appear in erc20 market segments
    %MarketSegment{
      name: "Qux",
      projects: [
        %Project{
          name: "Qux Project",
          coinmarketcap_id: "quxproject",
          main_contract_address: contract_address,
          infrastructure_id: btc_infrastructure.id
        }
      ]
    }
    |> Repo.insert!()

    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn, user: user}
  end

  test "all_market_segments/3", %{conn: conn} do
    market_segments =
      market_segments_query(conn, "allMarketSegments")
      |> json_response(200)
      |> extract_all_market_segments()

    assert Enum.count(market_segments) === 4

    assert market_segments === [
             %{"count" => 1, "name" => "Foo"},
             %{"count" => 1, "name" => "Bar"},
             %{"count" => 1, "name" => "Baz"},
             %{"count" => 1, "name" => "Qux"}
           ]
  end

  test "erc20_market_segments/3", %{conn: conn} do
    market_segments =
      market_segments_query(conn, "erc20MarketSegments")
      |> json_response(200)
      |> extract_erc20_market_segments()

    assert Enum.count(market_segments) === 1

    assert market_segments === [
             %{"count" => 1, "name" => "Foo"}
           ]
  end

  test "currencies_market_segments/3", %{conn: conn} do
    market_segments =
      market_segments_query(conn, "currenciesMarketSegments")
      |> json_response(200)
      |> extract_currencies_market_segments()

    assert Enum.count(market_segments) === 2

    assert market_segments === [
             %{"count" => 1, "name" => "Baz"},
             %{"count" => 1, "name" => "Qux"}
           ]
  end

  defp market_segments_query(conn, query_name) do
    query = """
    {
      #{query_name} {
        name,
        count
      }
    }
    """

    conn |> post("/graphql", query_skeleton(query, query_name))
  end

  defp extract_all_market_segments(%{"data" => %{"allMarketSegments" => all_market_segments}}) do
    all_market_segments
  end

  defp extract_erc20_market_segments(%{
         "data" => %{"erc20MarketSegments" => erc20_market_segments}
       }) do
    erc20_market_segments
  end

  defp extract_currencies_market_segments(%{
         "data" => %{"currenciesMarketSegments" => currencies_market_segments}
       }) do
    currencies_market_segments
  end
end
