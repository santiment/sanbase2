defmodule SanbaseWeb.Graphql.BalanceDataloader do
  @moduledoc false
  alias Sanbase.Clickhouse.HistoricalBalance

  def data, do: Dataloader.KV.new(&query/2)

  def query(:address_selector_current_balance, address_selector_pairs) do
    groups =
      Enum.group_by(
        address_selector_pairs,
        fn {_address, selector} -> selector end,
        fn {address, _selector} -> address end
      )

    groups
    |> Sanbase.Parallel.map(&get_current_balance/1,
      max_concurrency: 4,
      ordered: false,
      timeout: 55_000
    )
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
  end

  def query(:address_selector_balance_change, address_selector_from_to_tuples) do
    groups =
      Enum.group_by(
        address_selector_from_to_tuples,
        fn {_address, selector, from, to} -> %{selector: selector, from: from, to: to} end,
        fn {address, _selector, _from, _to} -> address end
      )

    groups
    |> Sanbase.Parallel.map(&get_balance_change/1,
      max_concurrency: 4,
      ordered: false,
      timeout: 55_000
    )
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
  end

  # Private functions

  defp get_current_balance({selector, addresses}) do
    addresses = Enum.uniq(addresses)

    case HistoricalBalance.current_balance(selector, addresses) do
      {:ok, list} ->
        balance_map =
          Enum.reduce(list, %{}, fn map, acc ->
            Map.put(acc, {map.address, selector}, map.balance)
          end)

        total_balance =
          Enum.reduce(balance_map, 0, fn
            {_, balance}, acc when is_number(balance) -> balance + acc
            _, acc -> acc
          end)

        Map.put(balance_map, {:total_balance, selector}, total_balance)

      {:error, _error} ->
        %{}
    end
  end

  defp get_balance_change({selector_from_to_map, addresses}) do
    %{selector: selector, from: from, to: to} = selector_from_to_map

    case HistoricalBalance.balance_change(selector, addresses, from, to) do
      {:ok, list} ->
        Enum.reduce(list, %{}, fn
          %{address: address} = result, acc ->
            Map.put(acc, {address, selector, from, to}, result)
        end)

      {:error, _error} ->
        %{}
    end
  end
end
