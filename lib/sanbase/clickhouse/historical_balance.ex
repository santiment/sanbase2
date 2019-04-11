defmodule Sanbase.Clickhouse.HistoricalBalance do
  alias Sanbase.Model.Project

  def balance_change(address, slug, from, to) do
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug) do
      case contract do
        "ETH" ->
          __MODULE__.EthBalance.balance_change(
            address,
            from,
            to
          )

        _ ->
          __MODULE__.Erc20Balance.balance_change(
            address,
            contract,
            token_decimals,
            from,
            to
          )
      end
    else
      {:error, error} -> {:error, inspect(error)}
    end
  end

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
    else
      {:error, error} -> {:error, inspect(error)}
    end
  end
end
