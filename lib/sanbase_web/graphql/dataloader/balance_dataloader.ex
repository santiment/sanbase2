defmodule SanbaseWeb.Graphql.BalanceDataloader do
  alias Sanbase.Clickhouse.HistoricalBalance

  require Logger

  # Above the 85s ClickHouse budget, so a slow query returns its own error, and below
  # the 105s Dataloader.KV source timeout. A group that still times out is killed and
  # dropped (its keys resolve to nil) instead of exiting the whole batch.
  # See docs/timeouts.md.
  @fan_out_timeout 95_000

  def query(:address_selector_current_balance, address_selector_pairs, ctx) do
    groups =
      Enum.group_by(
        address_selector_pairs,
        fn {_address, selector} -> selector end,
        fn {address, _selector} -> address end
      )

    Sanbase.Parallel.map(groups, &get_current_balance/1,
      max_concurrency: 4,
      ordered: false,
      timeout: @fan_out_timeout,
      on_timeout: :kill_task,
      zip_input_on_exit: true,
      request_context: ctx
    )
    |> merge_results(:address_selector_current_balance)
  end

  def query(:address_selector_balance_change, address_selector_from_to_tuples, ctx) do
    groups =
      address_selector_from_to_tuples
      |> Enum.group_by(
        fn {_address, selector, from, to} -> %{selector: selector, from: from, to: to} end,
        fn {address, _selector, _from, _to} -> address end
      )

    Sanbase.Parallel.map(groups, &get_balance_change/1,
      max_concurrency: 4,
      ordered: false,
      timeout: @fan_out_timeout,
      on_timeout: :kill_task,
      zip_input_on_exit: true,
      request_context: ctx
    )
    |> merge_results(:address_selector_balance_change)
  end

  # Private functions

  defp merge_results(results, query) do
    Enum.reduce(results, %{}, fn
      {:exit, {{_selector, addresses}, reason}}, acc ->
        Logger.warning(
          "BalanceDataloader #{inspect(query)} dropped #{length(addresses)} keys. Reason: #{inspect(reason)}"
        )

        acc

      map, acc ->
        Map.merge(acc, map)
    end)
  end

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
