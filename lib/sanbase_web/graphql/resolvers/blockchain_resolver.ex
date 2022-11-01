defmodule SanbaseWeb.Graphql.Resolvers.BlockchainResolver do
  @blockchains [
    "ethereum",
    "bitcoin",
    "bitcoin-cash",
    "litecoin",
    "ripple",
    "binance-coin",
    "dogecoin",
    "matic-network",
    "cardano",
    "avalanche",
    "optimism",
    "arbitrum"
  ]

  def available_blockchains_metadata(_root, _argsargs, _resolution) do
    {:ok, Enum.map(@blockchains, &blockchain_data/1)}
  end

  defp blockchain_data("ethereum") do
    %{
      blockchain: "ethereum",
      name: "Ethereum",
      slug: "ethereum",
      infrastructure: "ETH",
      created_on: ~U[2015-07-30 00:00:00Z],
      has_exchange_metrics: true,
      has_miners_metrics: true,
      has_label_metrics: true,
      has_top_holders_metrics: true,
      has_onchain_financial_metrics: true,
      has_pure_onchain_metrics: true,
      has_balance_metrics: true
    }
    |> add_complex_fields()
  end

  defp blockchain_data("bitcoin") do
    %{
      blockchain: "bitcoin",
      name: "Bitcoin",
      slug: "bitcoin",
      infrastructure: "BTC",
      created_on: ~U[2009-01-03 00:00:00Z],
      has_exchange_metrics: true,
      has_miners_metrics: true,
      has_label_metrics: false,
      has_top_holders_metrics: true,
      has_onchain_financial_metrics: true,
      has_pure_onchain_metrics: true,
      has_balance_metrics: true
    }
    |> add_complex_fields()
  end

  defp blockchain_data("bitcoin-cash") do
    %{
      blockchain: "bitcoin-cash",
      name: "Bitcoin Cash",
      slug: "bitcoin-cash",
      infrastructure: "BCH",
      created_on: ~U[2017-08-01 00:00:00Z],
      has_exchange_metrics: false,
      has_miners_metrics: false,
      has_label_metrics: false,
      has_top_holders_metrics: false,
      has_onchain_financial_metrics: true,
      has_pure_onchain_metrics: true,
      has_balance_metrics: true
    }
    |> add_complex_fields()
  end

  defp blockchain_data("litecoin") do
    %{
      blockchain: "litecoin",
      name: "Litecoin",
      slug: "litecoin",
      infrastructure: "LTC",
      created_on: ~U[2011-10-13 00:00:00Z],
      has_exchange_metrics: false,
      has_miners_metrics: false,
      has_label_metrics: false,
      has_top_holders_metrics: false,
      has_onchain_financial_metrics: true,
      has_pure_onchain_metrics: true,
      has_balance_metrics: true
    }
    |> add_complex_fields()
  end

  defp blockchain_data("ripple") do
    %{
      blockchain: "ripple",
      name: "Ripple",
      slug: "ripple",
      infrastructure: "Ripple",
      created_on: ~U[2013-01-02 00:00:00Z],
      has_exchange_metrics: false,
      has_miners_metrics: false,
      has_label_metrics: false,
      has_top_holders_metrics: false,
      has_onchain_financial_metrics: true,
      has_pure_onchain_metrics: true,
      has_balance_metrics: true
    }
    |> add_complex_fields()
  end

  defp blockchain_data("binance-coin") do
    %{
      blockchain: "binance-coin",
      name: "Binance Coin",
      slug: "binance-coin",
      infrastructure: "BEP20",
      created_on: ~U[2019-04-18 00:00:00Z],
      has_exchange_metrics: false,
      has_miners_metrics: false,
      has_label_metrics: false,
      has_top_holders_metrics: true,
      has_onchain_financial_metrics: true,
      has_pure_onchain_metrics: true,
      has_balance_metrics: true
    }
    |> add_complex_fields()
  end

  defp blockchain_data("dogecoin") do
    %{
      blockchain: "dogecoin",
      name: "Dogecoin",
      slug: "dogecoin",
      infrastructure: "DOGE",
      created_on: ~U[2013-12-08 00:00:00Z],
      has_exchange_metrics: false,
      has_miners_metrics: false,
      has_label_metrics: false,
      has_top_holders_metrics: false,
      has_onchain_financial_metrics: true,
      has_pure_onchain_metrics: true,
      has_balance_metrics: true
    }
    |> add_complex_fields()
  end

  defp blockchain_data("matic-network") do
    %{
      blockchain: "matic-network",
      name: "Matic Network",
      slug: "matic-network",
      infrastructure: "Polygon",
      created_on: ~U[2017-07-12 00:00:00Z],
      has_exchange_metrics: false,
      has_miners_metrics: false,
      has_label_metrics: false,
      has_top_holders_metrics: false,
      has_onchain_financial_metrics: true,
      has_pure_onchain_metrics: true,
      has_balance_metrics: true
    }
    |> add_complex_fields()
  end

  defp blockchain_data("cardano") do
    %{
      blockchain: "cardano",
      name: "Cardano",
      slug: "cardano",
      infrastructure: "Cardano",
      created_on: ~U[2017-09-23 00:00:00Z],
      has_exchange_metrics: false,
      has_miners_metrics: false,
      has_label_metrics: false,
      has_top_holders_metrics: false,
      has_onchain_financial_metrics: true,
      has_pure_onchain_metrics: true,
      has_balance_metrics: true
    }
    |> add_complex_fields()
  end

  defp blockchain_data("avalanche") do
    %{
      blockchain: "avalanche",
      name: "Avalanche",
      slug: "avalanche",
      infrastructure: "Avalanche",
      created_on: ~U[2020-10-01 22:15:46Z],
      has_exchange_metrics: false,
      has_miners_metrics: false,
      has_label_metrics: false,
      has_top_holders_metrics: false,
      has_onchain_financial_metrics: true,
      has_pure_onchain_metrics: true,
      has_balance_metrics: true
    }
    |> add_complex_fields()
  end

  defp blockchain_data("optimism") do
    %{
      blockchain: "optimism",
      name: "Optimism",
      slug: "optimism",
      infrastructure: "Optimism",
      created_on: ~U[2021-11-11 00:00:00Z],
      has_exchange_metrics: false,
      has_miners_metrics: false,
      has_label_metrics: false,
      has_top_holders_metrics: false,
      has_onchain_financial_metrics: true,
      has_pure_onchain_metrics: true,
      has_balance_metrics: true
    }
    |> add_complex_fields()
  end

  defp blockchain_data("arbitrum") do
    %{
      blockchain: "arbitrum",
      name: "Arbitrum",
      slug: "arbitrum",
      infrastructure: "Arbitrum",
      created_on: ~U[2021-05-30 00:00:00Z],
      has_exchange_metrics: false,
      has_miners_metrics: false,
      has_label_metrics: false,
      has_top_holders_metrics: false,
      has_onchain_financial_metrics: true,
      has_pure_onchain_metrics: true,
      has_balance_metrics: true
    }
    |> add_complex_fields()
  end

  defp add_complex_fields(%{} = map) do
    map
    |> Map.put(
      :has_exchange_top_holders_metrics,
      map.has_exchange_metrics and map.has_top_holders_metrics
    )
  end
end
