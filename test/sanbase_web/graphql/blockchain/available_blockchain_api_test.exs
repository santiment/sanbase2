defmodule SanbaseWeb.Graphql.AvailableBlockchainApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers

  test "Ethereum recent transactions" do
    result = get_available_blockchains()

    assert result == [
             %{
               "blockchain" => "ethereum",
               "hasBalanceMetrics" => true,
               "hasExchangeMetrics" => true,
               "hasMinersMetrics" => true,
               "hasOnchainFinancialMetrics" => true,
               "hasPureOnchainMetrics" => true,
               "hasTopHoldersMetrics" => true,
               "infrastructure" => "ETH",
               "slug" => "ethereum"
             },
             %{
               "blockchain" => "bitcoin",
               "hasBalanceMetrics" => true,
               "hasExchangeMetrics" => true,
               "hasMinersMetrics" => true,
               "hasOnchainFinancialMetrics" => true,
               "hasPureOnchainMetrics" => true,
               "hasTopHoldersMetrics" => true,
               "infrastructure" => "BTC",
               "slug" => "bitcoin"
             },
             %{
               "blockchain" => "bitcoin-cash",
               "hasBalanceMetrics" => true,
               "hasExchangeMetrics" => false,
               "hasMinersMetrics" => false,
               "hasOnchainFinancialMetrics" => true,
               "hasPureOnchainMetrics" => true,
               "hasTopHoldersMetrics" => false,
               "infrastructure" => "BCH",
               "slug" => "bitcoin-cash"
             },
             %{
               "blockchain" => "litecoin",
               "hasBalanceMetrics" => true,
               "hasExchangeMetrics" => false,
               "hasMinersMetrics" => false,
               "hasOnchainFinancialMetrics" => true,
               "hasPureOnchainMetrics" => true,
               "hasTopHoldersMetrics" => false,
               "infrastructure" => "LTC",
               "slug" => "litecoin"
             },
             %{
               "blockchain" => "ripple",
               "hasBalanceMetrics" => true,
               "hasExchangeMetrics" => false,
               "hasMinersMetrics" => false,
               "hasOnchainFinancialMetrics" => true,
               "hasPureOnchainMetrics" => true,
               "hasTopHoldersMetrics" => false,
               "infrastructure" => "Ripple",
               "slug" => "ripple"
             },
             %{
               "blockchain" => "binance-coin",
               "hasBalanceMetrics" => true,
               "hasExchangeMetrics" => false,
               "hasMinersMetrics" => false,
               "hasOnchainFinancialMetrics" => true,
               "hasPureOnchainMetrics" => true,
               "hasTopHoldersMetrics" => true,
               "infrastructure" => "BEP20",
               "slug" => "binance-coin"
             },
             %{
               "blockchain" => "dogecoin",
               "hasBalanceMetrics" => true,
               "hasExchangeMetrics" => false,
               "hasMinersMetrics" => false,
               "hasOnchainFinancialMetrics" => true,
               "hasPureOnchainMetrics" => true,
               "hasTopHoldersMetrics" => false,
               "infrastructure" => "DOGE",
               "slug" => "dogecoin"
             },
             %{
               "blockchain" => "matic-network",
               "hasBalanceMetrics" => true,
               "hasExchangeMetrics" => false,
               "hasMinersMetrics" => false,
               "hasOnchainFinancialMetrics" => true,
               "hasPureOnchainMetrics" => true,
               "hasTopHoldersMetrics" => false,
               "infrastructure" => "Polygon",
               "slug" => "matic-network"
             },
             %{
               "blockchain" => "cardano",
               "hasBalanceMetrics" => true,
               "hasExchangeMetrics" => false,
               "hasMinersMetrics" => false,
               "hasOnchainFinancialMetrics" => true,
               "hasPureOnchainMetrics" => true,
               "hasTopHoldersMetrics" => false,
               "infrastructure" => "Cardano",
               "slug" => "cardano"
             },
             %{
               "blockchain" => "avalanche",
               "hasBalanceMetrics" => true,
               "hasExchangeMetrics" => false,
               "hasMinersMetrics" => false,
               "hasOnchainFinancialMetrics" => true,
               "hasPureOnchainMetrics" => true,
               "hasTopHoldersMetrics" => false,
               "infrastructure" => "Avalanche",
               "slug" => "avalanche"
             },
             %{
               "blockchain" => "optimism",
               "hasBalanceMetrics" => true,
               "hasExchangeMetrics" => false,
               "hasMinersMetrics" => false,
               "hasOnchainFinancialMetrics" => true,
               "hasPureOnchainMetrics" => true,
               "hasTopHoldersMetrics" => false,
               "infrastructure" => "Optimism",
               "slug" => "optimism"
             }
           ]
  end

  defp get_available_blockchains() do
    query = """
    {
      getAvailableBlockchains{
        slug
        blockchain
        infrastructure
        hasMinersMetrics
        hasBalanceMetrics
        hasExchangeMetrics
        hasTopHoldersMetrics
        hasOnchainFinancialMetrics
        hasPureOnchainMetrics
      }
    }
    """

    build_conn()
    |> post("/graphql", query_skeleton(query, "getAvailableBlockchains"))
    |> json_response(200)
    |> get_in(["data", "getAvailableBlockchains"])
  end
end
