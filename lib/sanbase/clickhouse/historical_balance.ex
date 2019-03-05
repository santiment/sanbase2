defmodule Sanbase.Clickhouse.HistoricalBalance do
  alias Sanbase.Model.Project

  def historical_balance(address, slug, from, to, interval) do
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug) do
      case contract do
        "ETH" ->
          __MODULE__.EthBalance.historical_balance(
            address,
            from,
            to,
            interval
          )

        _ ->
          __MODULE__.Erc20Balance.historical_balance(
            address,
            contract,
            token_decimals,
            from,
            to,
            interval
          )
      end
    end
  end
end
