defmodule Sanbase.Balance do
  import __MODULE__.SqlQuery

  import Sanbase.Clickhouse.HistoricalBalance.Utils,
    only: [maybe_update_first_balance: 2, maybe_fill_gaps_last_seen_balance: 1]

  alias Sanbase.ClickhouseRepo
  alias Sanbase.Model.Project

  def historical_balance_ohlc(address, slug, from, to, interval) do
    with {:ok, _contract, decimals, infr} <- Project.contract_info_infrastructure_by_slug(slug) do
      blockchain = blockchain_from_infrastructure(infr)
      address = transform_address(address, blockchain)

      do_historical_balance_ohlc(address, slug, decimals, blockchain, from, to, interval)
    end
  end

  def historical_balance(address, slug, from, to, interval) do
    with {:ok, _contract, decimals, infr} <- Project.contract_info_infrastructure_by_slug(slug) do
      blockchain = blockchain_from_infrastructure(infr)
      address = transform_address(address, blockchain)

      do_historical_balance(address, slug, decimals, blockchain, from, to, interval)
    end
  end

  def balance_change(address_or_addresses, slug, from, to) do
    with {:ok, _contract, decimals, infr} <- Project.contract_info_infrastructure_by_slug(slug) do
      blockchain = blockchain_from_infrastructure(infr)
      addresses = List.wrap(address_or_addresses) |> transform_address(blockchain)

      do_balance_change(addresses, slug, decimals, blockchain, from, to)
    end
  end

  def historical_balance_changes(address_or_addresses, slug, from, to, interval) do
    with {:ok, _contract, decimals, infr} <- Project.contract_info_infrastructure_by_slug(slug) do
      blockchain = blockchain_from_infrastructure(infr)
      addresses = List.wrap(address_or_addresses) |> transform_address(blockchain)

      do_historical_balance_changes(addresses, slug, decimals, blockchain, from, to, interval)
    end
  end

  def last_balance_before(address, slug, datetime) do
    with {:ok, _contract, decimals, infr} <- Project.contract_info_infrastructure_by_slug(slug) do
      blockchain = blockchain_from_infrastructure(infr)
      address = transform_address(address, blockchain)

      do_last_balance_before(address, slug, decimals, blockchain, datetime)
    end
  end

  def assets_held_by_address(address) do
    address = transform_address(address, :unknown)
    {query, args} = assets_held_by_address_query(address)

    ClickhouseRepo.query_transform(query, args, fn [slug, balance] ->
      %{
        slug: slug,
        balance: balance
      }
    end)
  end

  def current_balance(address_or_addresses, slug) do
    with {:ok, _contract, decimals, infr} <- Project.contract_info_infrastructure_by_slug(slug) do
      blockchain = blockchain_from_infrastructure(infr)
      addresses = List.wrap(address_or_addresses) |> transform_address(blockchain)
      do_current_balance(addresses, slug, decimals, blockchain)
    end
  end

  # Private functions

  defp do_current_balance(addresses, slug, decimals, blockchain) do
    {query, args} = current_balance_query(addresses, slug, decimals, blockchain)

    ClickhouseRepo.query_transform(query, args, fn [address, balance] ->
      %{
        addresses: address,
        balance: balance
      }
    end)
  end

  defp do_balance_change(addresses, slug, decimals, blockchain, from, to) do
    {query, args} = balance_change_query(addresses, slug, decimals, blockchain, from, to)

    ClickhouseRepo.query_transform(query, args, fn
      [address, balance_start, balance_end, balance_change] ->
        %{
          address: address,
          balance_start: balance_start,
          balance_end: balance_end,
          balance_change_amount: balance_change,
          balance_change_percent: Sanbase.Math.percent_change(balance_start, balance_end)
        }
    end)
  end

  defp do_historical_balance_changes(addresses, slug, decimals, blockchain, from, to, interval) do
    {query, args} =
      historical_balance_changes_query(addresses, slug, decimals, blockchain, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [unix, balance_change] ->
      %{
        datetime: DateTime.from_unix!(unix),
        balance_change_amount: balance_change
      }
    end)
  end

  defp do_last_balance_before(address, slug, decimals, blockchain, datetime) do
    {query, args} = last_balance_before_query(address, slug, decimals, blockchain, datetime)

    case ClickhouseRepo.query_transform(query, args, & &1) do
      {:ok, [[balance]]} -> {:ok, balance}
      {:ok, []} -> {:ok, 0}
      {:error, error} -> {:error, error}
    end
  end

  defp do_historical_balance(address, slug, decimals, blockchain, from, to, interval) do
    {query, args} =
      historical_balance_query(address, slug, decimals, blockchain, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [unix, value, has_changed] ->
      %{
        datetime: DateTime.from_unix!(unix),
        balance: value,
        has_changed: has_changed
      }
    end)
    |> maybe_update_first_balance(fn ->
      do_last_balance_before(address, slug, decimals, blockchain, from)
    end)
    |> maybe_fill_gaps_last_seen_balance()
  end

  defp do_historical_balance_ohlc(address, slug, decimals, blockchain, from, to, interval) do
    {query, args} =
      historical_balance_ohlc_query(address, slug, decimals, blockchain, from, to, interval)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [unix, open, high, low, close, has_changed] ->
        %{
          datetime: DateTime.from_unix!(unix),
          open_balance: open,
          high_balance: high,
          low_balance: low,
          close_balance: close,
          has_changed: has_changed
        }
      end
    )
    |> maybe_update_first_balance(fn ->
      do_last_balance_before(address, slug, decimals, blockchain, from)
    end)
    |> maybe_fill_gaps_last_seen_balance()
  end

  defp blockchain_from_infrastructure("ETH"), do: "ethereum"
  defp blockchain_from_infrastructure("BTC"), do: "bitcoin"
  defp blockchain_from_infrastructure("XRP"), do: "ripple"

  defp transform_address("0x" <> _rest = address, :unknown),
    do: String.downcase(address)

  defp transform_address(address, :unknown) when is_binary(address), do: address

  defp transform_address(addresses, :unknown) when is_list(addresses),
    do: addresses |> List.flatten() |> Enum.map(&transform_address(&1, :unknown))

  defp transform_address(address, "ethereum") when is_binary(address),
    do: String.downcase(address)

  defp transform_address(addresses, "ethereum") when is_list(addresses),
    do: addresses |> List.flatten() |> Enum.map(&String.downcase/1)

  defp transform_address(address, _) when is_binary(address), do: address

  defp transform_address(addresses, _) when is_list(addresses),
    do: List.flatten(addresses)
end
