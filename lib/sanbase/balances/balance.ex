defmodule Sanbase.Balance do
  import __MODULE__.SqlQuery

  import Sanbase.Utils.Transform, only: [maybe_unwrap_ok_value: 1]

  import Sanbase.Clickhouse.HistoricalBalance.Utils,
    only: [maybe_update_first_balance: 2, maybe_fill_gaps_last_seen_balance: 1]

  alias Sanbase.ClickhouseRepo
  alias Sanbase.Model.Project

  def historical_balance_ohlc([], _slug, _from, _to, _interval), do: {:ok, []}

  def historical_balance_ohlc(address, slug, from, to, interval) do
    with {:ok, {decimals, _infr, blockchain}} <- info_by_slug(slug) do
      address = transform_address(address, blockchain)

      do_historical_balance_ohlc(address, slug, decimals, blockchain, from, to, interval)
    end
  end

  def historical_balance(address, slug, from, to, interval) when is_binary(address) do
    with {:ok, {decimals, _infr, blockchain}} <- info_by_slug(slug) do
      address = transform_address(address, blockchain)

      do_historical_balance(address, slug, decimals, blockchain, from, to, interval)
    end
  end

  def balance_change([], _slug, _from, _to), do: {:ok, []}

  def balance_change(address_or_addresses, slug, from, to) do
    with {:ok, {decimals, _infr, blockchain}} <- info_by_slug(slug) do
      addresses = List.wrap(address_or_addresses) |> transform_address(blockchain)

      do_balance_change(addresses, slug, decimals, blockchain, from, to)
    end
  end

  def historical_balance_changes([], _slug, _from, _to, _interval),
    do: {:ok, []}

  def historical_balance_changes(address_or_addresses, slug, from, to, interval) do
    with {:ok, {decimals, _infr, blockchain}} <- info_by_slug(slug) do
      addresses = List.wrap(address_or_addresses) |> transform_address(blockchain)

      do_historical_balance_changes(addresses, slug, decimals, blockchain, from, to, interval)
    end
  end

  def last_balance_before(address_or_addresses, slug, datetime) do
    with {:ok, {decimals, _infr, blockchain}} <- info_by_slug(slug) do
      addresses = List.wrap(address_or_addresses) |> transform_address(blockchain)

      do_last_balance_before(addresses, slug, decimals, blockchain, datetime)
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

  def addresses_by_filter(slug, operator, threshold, opts) do
    with {:ok, {decimals, infr, _blockchain}} <- info_by_slug(slug),
         {:ok, table} <- realtime_balances_table(slug, infr) do
      {query, args} = addresses_by_filter_query(slug, decimals, operator, threshold, table, opts)

      ClickhouseRepo.query_transform(query, args, fn [address, balance] ->
        %{
          address: address,
          balance: balance
        }
      end)
    end
  end

  def first_datetime(address, slug) do
    with {:ok, {_decimals, _infr, blockchain}} <- info_by_slug(slug) do
      address = transform_address(address, blockchain)

      {query, args} = first_datetime_query(address, slug, blockchain)

      ClickhouseRepo.query_transform(query, args, fn [unix] -> DateTime.from_unix!(unix) end)
      |> maybe_unwrap_ok_value()
    end
  end

  def current_balance(address_or_addresses, slug) do
    with {:ok, {decimals, infr, blockchain}} <- info_by_slug(slug),
         {:ok, table} <- realtime_balances_table_or_nil(slug, infr) do
      addresses = List.wrap(address_or_addresses) |> transform_address(blockchain)

      do_current_balance(addresses, slug, decimals, blockchain, table)
    end
  end

  def current_balance_top_addresses(slug, opts) do
    with {:ok, {decimals, infrastructure, blockchain}} <- info_by_slug(slug),
         {:ok, table} <- realtime_balances_table(slug, infrastructure) do
      {query, args} = top_addresses_query(slug, decimals, blockchain, table, opts)

      ClickhouseRepo.query_transform(query, args, fn [address, balance] ->
        %{
          address: address,
          infrastructure: infrastructure,
          balance: balance
        }
      end)
    end
  end

  def realtime_balances_table_or_nil(slug, infr) do
    case realtime_balances_table(slug, infr) do
      {:ok, table} -> {:ok, table}
      _ -> {:ok, nil}
    end
  end

  def realtime_balances_table("ethereum", "ETH"), do: {:ok, "eth_balances_realtime"}
  def realtime_balances_table(_, "ETH"), do: {:ok, "erc20_balances_realtime"}

  def realtime_balances_table(slug, _infrastructure),
    do: {:error, "The slug #{slug} does not have support for realtime balances"}

  def supported_infrastructures(), do: ["ETH", "BTC", "BCH", "LTC", "BNB", "BEP2", "XRP"]

  def blockchain_from_infrastructure("ETH"), do: "ethereum"
  def blockchain_from_infrastructure("BTC"), do: "bitcoin"
  def blockchain_from_infrastructure("BCH"), do: "bitcoin-cash"
  def blockchain_from_infrastructure("LTC"), do: "litecoin"
  def blockchain_from_infrastructure("BNB"), do: "binance"
  def blockchain_from_infrastructure("BEP2"), do: "binance"
  def blockchain_from_infrastructure("XRP"), do: "ripple"
  def blockchain_from_infrastructure(_), do: :unsupported_blockchain

  # Private functions

  defp do_current_balance(addresses, slug, decimals, blockchain, table) do
    {query, args} = current_balance_query(addresses, slug, decimals, blockchain, table)

    ClickhouseRepo.query_transform(query, args, fn [address, balance] ->
      %{
        address: address,
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

  defp do_historical_balance_changes(
         addresses,
         slug,
         decimals,
         blockchain,
         from,
         to,
         interval
       ) do
    {query, args} =
      historical_balance_changes_query(
        addresses,
        slug,
        decimals,
        blockchain,
        from,
        to,
        interval
      )

    ClickhouseRepo.query_transform(query, args, fn [unix, balance_change] ->
      %{
        datetime: DateTime.from_unix!(unix),
        balance_change_amount: balance_change
      }
    end)
  end

  defp do_last_balance_before(
         address_or_addresse,
         slug,
         decimals,
         blockchain,
         datetime
       ) do
    addresses =
      address_or_addresse
      |> List.wrap()
      |> Enum.map(&transform_address(&1, blockchain))

    {query, args} = last_balance_before_query(addresses, slug, decimals, blockchain, datetime)

    case ClickhouseRepo.query_transform(query, args, & &1) do
      {:ok, list} ->
        # If an address does not own the given coin/token, it will be missing from the
        # result. Iterate it like this in order to fill the missing values with 0
        map = Map.new(list, fn [address, balance] -> {address, balance} end)
        result = Enum.into(addresses, %{}, &{&1, Map.get(map, &1, 0)})

        {:ok, result}

      {:error, error} ->
        {:error, error}
    end
  end

  defp do_historical_balance(
         address,
         slug,
         decimals,
         blockchain,
         from,
         to,
         interval
       ) do
    {query, args} =
      historical_balance_query(
        address,
        slug,
        decimals,
        blockchain,
        from,
        to,
        interval
      )

    ClickhouseRepo.query_transform(query, args, fn [unix, value, has_changed] ->
      %{
        datetime: DateTime.from_unix!(unix),
        balance: value,
        has_changed: has_changed
      }
    end)
    |> maybe_update_first_balance(fn ->
      case do_last_balance_before(address, slug, decimals, blockchain, from) do
        {:ok, %{^address => balance}} -> {:ok, balance}
        {:error, error} -> {:error, error}
      end
    end)
    |> maybe_fill_gaps_last_seen_balance()
  end

  defp do_historical_balance_ohlc(
         address,
         slug,
         decimals,
         blockchain,
         from,
         to,
         interval
       ) do
    {query, args} =
      historical_balance_ohlc_query(
        address,
        slug,
        decimals,
        blockchain,
        from,
        to,
        interval
      )

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
      case do_last_balance_before(address, slug, decimals, blockchain, from) do
        {:ok, %{^address => balance}} -> {:ok, balance}
        {:error, error} -> {:error, error}
      end
    end)
    |> maybe_fill_gaps_last_seen_balance()
  end

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

  defp info_by_slug(slug) do
    case Project.contract_info_infrastructure_by_slug(slug) do
      {:ok, _contract, decimals, infr} ->
        case blockchain_from_infrastructure(infr) do
          :unsupported_blockchain ->
            {:error,
             """
             Project with slug #{slug} has #{infr} infrastructure which does not \
             have support for historical balances.
             """}

          blockchain ->
            decimals = maybe_override_decimals(blockchain, decimals)
            {:ok, {decimals, infr, blockchain}}
        end

      {:error, {:missing_contract, error}} ->
        {:error, error}
    end
  end

  # The values for all other chains except ethereum (ethereum itself and all ERC20 assets)
  # are stored already divided by the decimals. In these cases replace decimals with 0
  # so the division of 10^0 will do nothing.
  defp maybe_override_decimals("ethereum", decimals), do: decimals
  defp maybe_override_decimals(_blockchain, _decimal), do: 0
end
