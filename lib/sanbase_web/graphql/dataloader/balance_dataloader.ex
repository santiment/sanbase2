defmodule SanbaseWeb.Graphql.BalanceDataloader do
  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.HistoricalBalance

  def data(), do: Dataloader.KV.new(&query/2)

  def query(:current_address_selector_balance, address_selector_pairs) do
    selector_groups =
      Enum.group_by(
        address_selector_pairs,
        fn {_address, selector} -> selector end,
        fn {address, _selector} -> address end
      )

    Sanbase.Parallel.map(selector_groups, &get_balance/1,
      max_concurrency: 4,
      ordered: false,
      timeout: 55_000
    )
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
  end

  defp get_balance({selector, addresses}) do
    case HistoricalBalance.current_balance(selector, addresses) do
      {:ok, list} ->
        Enum.reduce(list, %{}, fn map, acc ->
          Map.put(acc, {map.address, selector}, map.balance)
        end)

      {:error, _error} ->
        %{}
    end
  end
end
