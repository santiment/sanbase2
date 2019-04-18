defmodule Sanbase.Clickhouse.HistoricalBalance do
  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.HistoricalBalance.{EthBalance, Erc20Balance}

  def eth_balance_change(addresses, from, to) do
    EthBalance.balance_change(addresses, from, to)
  end

  def eth_balance_change(addresses, from, to, interval) do
    EthBalance.balance_change(addresses, from, to, interval)
  end

  def balance_change(address, slug, from, to) do
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug) do
      case contract do
        "ETH" ->
          EthBalance.balance_change(address, from, to)

        _ ->
          Erc20Balance.balance_change(address, contract, token_decimals, from, to)
      end
    else
      {:error, error} -> {:error, inspect(error)}
    end
  end

  def historical_balance(address, slug, from, to, interval) do
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug) do
      case contract do
        "ETH" ->
          EthBalance.historical_balance(address, from, to, interval)

        _ ->
          Erc20Balance.historical_balance(address, contract, token_decimals, from, to, interval)
      end
    else
      {:error, error} -> {:error, inspect(error)}
    end
  end

  def eth_spent(addresses, from, to) do
    with {:ok, balance_changes} <- eth_balance_change(addresses, from, to) do
      eth_spent =
        balance_changes
        |> Enum.map(fn {_, {_, _, change}} -> change end)
        |> Enum.sum()
        |> case do
          change when change < 0 -> abs(change)
          _ -> 0
        end

      {:ok, eth_spent}
    end
  end

  def eth_spent_over_time(addresses, from, to, interval)
      when is_binary(addresses) or is_list(addresses) do
    with {:ok, balance_changes} <- eth_balance_change(addresses, from, to, interval) do
      eth_spent_over_time =
        balance_changes
        |> Enum.map(fn
          %{balance_change: change, datetime: dt} = elem when change < 0 ->
            %{datetime: dt, eth_spent: abs(change)}

          %{datetime: dt} ->
            %{eth_spent: 0, datetime: dt}
        end)

      {:ok, eth_spent_over_time}
    end
  end
end
