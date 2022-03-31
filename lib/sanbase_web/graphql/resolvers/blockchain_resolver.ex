defmodule SanbaseWeb.Graphql.Resolvers.BlockchainResolver do
  @blockchains ["ethereum", "bitcoin", "bitcoin-cash", "litecoin", "ripple", "binance-coin", "dogecoin", "polygon", "cardano"]

  def available_blockchains_metadata(_root, _argsargs, _resolution) do
    {:ok, Enum.map(@blockchains, &blockchain_data/1)}
  end

  defp blockchain_data("ethereum") do
    %{
      blockchain: "ethereum",
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
      slug: "bitcoin",
      infrastructure: "BTC",
      created_on: ~U[2009-01-03 00:00:00Z],
      has_exchange_metrics: true,
      has_miners_metrics: false,
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
      slug: "ripple",
      infrastructure: "XRP",
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
      slug: "binance-coin",
      infrastructure: "BNB",
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

  defp blockchain_data("polygon") do
    %{
      blockchain: "polygon",
      slug: "polygon",
      infrastructure: "POLYGON",
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
      slug: "cardano",
      infrastructure: "ADA",
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

  defp add_complex_fields(%{} = map) do
    map
    |> Map.put(
      :has_exchange_top_holders_metrics,
      map.has_exchange_metrics and map.has_top_holders_metrics
    )
  end
end
