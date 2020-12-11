defmodule SanbaseWeb.Graphql.BalanceDataloader do
  alias Sanbase.Clickhouse.HistoricalBalance

  def data(), do: Dataloader.KV.new(&query/2)

  def query(:address_selector_current_balance, address_selector_pairs) do
    groups =
      Enum.group_by(
        address_selector_pairs,
        fn {_address, selector} -> selector end,
        fn {address, _selector} -> address end
      )

    Sanbase.Parallel.map(groups, &get_current_balance/1,
      max_concurrency: 4,
      ordered: false,
      timeout: 55_000
    )
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
  end

  def query(:address_selector_balance_change, address_selector_from_to_tuples) do
    groups =
      address_selector_from_to_tuples
      |> Enum.group_by(
        fn {_address, selector, from, to} -> %{selector: selector, from: from, to: to} end,
        fn {address, _selector, _from, _to} -> address end
      )

    Sanbase.Parallel.map(groups, &get_balance_change/1,
      max_concurrency: 4,
      ordered: false,
      timeout: 55_000
    )
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
  end

  # Private functions

  defp get_current_balance({selector, addresses}) do
    case HistoricalBalance.current_balance(selector, addresses) do
      {:ok, list} ->
        Enum.reduce(list, %{}, fn map, acc ->
          Map.put(acc, {map.address, selector}, map.balance)
        end)

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
