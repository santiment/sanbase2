defmodule Sanbase.Balance do
  import __MODULE__.SqlQuery

  import Sanbase.Utils.Transform,
    only: [maybe_unwrap_ok_value: 1, maybe_apply_function: 2, maybe_sort: 3]

  import Sanbase.Clickhouse.HistoricalBalance.Utils,
    only: [maybe_update_first_balance: 2, maybe_fill_gaps_last_seen_balance: 1]

  alias Sanbase.ClickhouseRepo
  alias Sanbase.Project

  @type slug :: String.t()
  @type address :: String.t()
  @type interval :: String.t()
  @type operator :: Sanbase.Metric.SqlQuery.Helper.operator()

  @doc ~s"""
  Return timeseries OHLC data for balances. For every point in time
  return the first, max, min and last balances for an `interval` period
  of time starting with that datetime.
  """
  @spec historical_balance_ohlc(
          list(address),
          slug,
          DateTime.t(),
          DateTime.t(),
          interval
        ) ::
          {:ok,
           list(%{
             datetime: DateTime.t(),
             open_balance: number(),
             high_balance: number(),
             low_balance: number(),
             close_balance: number()
           })}
          | {:error, String.t()}
  def historical_balance_ohlc([], _slug, _from, _to, _interval), do: {:ok, []}

  def historical_balance_ohlc(address, slug, from, to, interval) do
    with {:ok, {decimals, _infr, blockchain}} <- info_by_slug(slug) do
      address = Sanbase.BlockchainAddress.to_internal_format(address)

      do_historical_balance_ohlc(
        address,
        slug,
        decimals,
        blockchain,
        from,
        to,
        interval
      )
    end
  end

  @doc ~s"""
  Return timeseries data for balances. For every point in time
  return the last balance that is associated with that datetime.s
  """
  @spec historical_balance(address, slug, DateTime.t(), DateTime.t(), interval) ::
          {:ok, list(%{datetime: DateTime.t(), balance: number()})}
          | {:error, String.t()}
  def historical_balance(address, slug, from, to, interval)
      when is_binary(address) do
    with {:ok, {decimals, _infr, blockchain}} <- info_by_slug(slug) do
      address = Sanbase.BlockchainAddress.to_internal_format(address)

      do_historical_balance(
        address,
        slug,
        decimals,
        blockchain,
        from,
        to,
        interval
      )
    end
  end

  @doc ~s"""
  Return the balance changes data for every address in the list in the specified
  time range.
  """
  @spec balance_change(list(), String.t(), DateTime.t(), DateTime.t()) ::
          {:ok,
           %{
             address: String.t(),
             balance_start: number(),
             balance_end: number(),
             balance_change_amount: number(),
             balance_change_percent: number()
           }}
          | {:error, String.t()}
  def balance_change([], _slug, _from, _to), do: {:ok, []}

  def balance_change(address_or_addresses, slug, from, to) do
    with {:ok, {decimals, _infr, blockchain}} <- info_by_slug(slug) do
      addresses =
        address_or_addresses
        |> List.wrap()
        |> Sanbase.BlockchainAddress.to_internal_format()

      do_balance_change(addresses, slug, decimals, blockchain, from, to)
    end
  end

  @doc ~s"""
  Return the combined balance changes over time (one for every time bucket). This
  does not return the balance changes for every address separately, but sums all
  the changes for a given date so it must be used with addresses that belong
  to the same entity such as the wallets of a given crypto project. This the
  transfers between those wallets can be ignored and only transfers going outside
  the set or coming in are counted.
  """
  @spec historical_balance_changes(
          list(address),
          slug,
          DateTime.t(),
          DateTime.t(),
          interval
        ) ::
          {:ok,
           list(%{
             datetime: DateTime.t(),
             balance_change_amount: number(),
             balance_change_percent: number()
           })}
          | {:error, String.t()}
  def historical_balance_changes([], _slug, _from, _to, _interval),
    do: {:ok, []}

  def historical_balance_changes(address_or_addresses, slug, from, to, interval) do
    with {:ok, {decimals, _infr, blockchain}} <- info_by_slug(slug) do
      addresses =
        address_or_addresses
        |> List.wrap()
        |> Sanbase.BlockchainAddress.to_internal_format()

      do_historical_balance_changes(
        addresses,
        slug,
        decimals,
        blockchain,
        from,
        to,
        interval
      )
    end
  end

  @doc ~s"""
  Return the last known balance at or before `datetime` for every address
  provided as the first argument.
  """
  @spec last_balance_before(address | list(address), slug, DateTime.t()) ::
          {:ok, %{address => number()}} | {:error, String.t()}
  def last_balance_before(address_or_addresses, slug, datetime) do
    with {:ok, {decimals, _infr, blockchain}} <- info_by_slug(slug) do
      addresses =
        address_or_addresses
        |> List.wrap()
        |> Sanbase.BlockchainAddress.to_internal_format()

      do_last_balance_before(addresses, slug, decimals, blockchain, datetime)
    end
  end

  @doc ~s"""
  Return a list of all the assets that a given address holds. For every
  such asset return the slug and current balance. If some project is not
  in Santiment's database it is not shown.
  """
  @spec assets_held_by_address(address, Keyword.t()) ::
          {:ok, list(%{slug: slug, balance: number()})} | {:error, String.t()}
  def assets_held_by_address(address, opts \\ []) do
    address = Sanbase.BlockchainAddress.to_internal_format(address)

    hidden_projects_slugs = hidden_projects_slugs()

    assets_held_by_address_query(address, opts)
    |> ClickhouseRepo.query_transform(fn [slug, balance] ->
      %{
        slug: slug,
        balance: balance
      }
    end)
    |> maybe_apply_function(fn data -> Enum.reject(data, &(&1.slug in hidden_projects_slugs)) end)
  end

  def usd_value_address_change(address, datetime) do
    address = Sanbase.BlockchainAddress.to_internal_format(address)
    query_struct = usd_value_address_change_query(address, datetime)

    ClickhouseRepo.query_transform(
      query_struct,
      fn [
           slug,
           previous_balance,
           current_balance,
           previous_price_usd,
           current_price_usd,
           previous_usd_value,
           current_usd_value
         ] ->
        %{
          slug: slug,
          previous_balance: previous_balance,
          current_balance: current_balance,
          balance_change: previous_balance - current_balance,
          previous_price_usd: previous_price_usd,
          current_price_usd: current_price_usd,
          previous_usd_value: previous_usd_value,
          current_usd_value: current_usd_value,
          usd_value_change: previous_usd_value - current_usd_value
        }
      end
    )
    |> maybe_apply_function(fn data ->
      hidden_projects_slugs = hidden_projects_slugs()
      Enum.reject(data, &(&1.slug in hidden_projects_slugs))
    end)
    |> maybe_apply_function(fn data ->
      Enum.sort_by(data, & &1.usd_value_change, :desc)
    end)
  end

  def usd_value_held_by_address(address) do
    address = Sanbase.BlockchainAddress.to_internal_format(address)
    query_struct = usd_value_held_by_address_query(address)
    hidden_projects_slugs = hidden_projects_slugs()

    ClickhouseRepo.query_transform(
      query_struct,
      fn [slug, current_balance, current_price_usd, current_usd_value] ->
        %{
          slug: slug,
          current_balance: current_balance,
          current_price_usd: current_price_usd,
          current_usd_value: current_usd_value
        }
      end
    )
    |> maybe_apply_function(fn data -> Enum.reject(data, &(&1.slug in hidden_projects_slugs)) end)
    |> maybe_sort(:current_usd_value, :desc)
  end

  @doc ~s"""
  Return all addresses that have balance that matches a set of filters.
  The operator shows how the comparison must be done (:greater_than, :less_than, etc.any)
  and the balance is compared against the `threshold`. The addresses
  that match this filter are returned.
  Note that filters like `greater_than 0` or `less_than 100000` can return
  many addresses. Because of this there is a built-in limit of 10000.
  """
  @spec addresses_by_filter(slug, operator, number(), Keyword.t()) ::
          {:ok} | {:error, String.t()}
  def addresses_by_filter(slug, operator, threshold, opts) do
    with {:ok, {decimals, infr, _blockchain}} <- info_by_slug(slug),
         {:ok, table} <- realtime_balances_table(slug, infr) do
      query_struct = addresses_by_filter_query(slug, decimals, operator, threshold, table, opts)

      ClickhouseRepo.query_transform(query_struct, fn [address, balance] ->
        %{
          address: address,
          balance: balance
        }
      end)
    end
  end

  @doc ~s"""
  Return the first datetime for which there is a balance record for a
  given address/slug pair.
  """
  @spec first_datetime(address, slug) ::
          {:ok, DateTime.t()} | {:error, String.t()}
  def first_datetime(address, slug) do
    with {:ok, {_decimals, _infr, blockchain}} <- info_by_slug(slug) do
      address = Sanbase.BlockchainAddress.to_internal_format(address)
      query_struct = first_datetime_query(address, slug, blockchain)

      ClickhouseRepo.query_transform(query_struct, fn [unix] ->
        DateTime.from_unix!(unix)
      end)
      |> maybe_unwrap_ok_value()
    end
  end

  @doc ~s"""
  Return the current balance for every address provided and a given slu
  """
  @spec current_balance(address | list(address), slug) ::
          {:ok, [%{address: address, balance: number()}]} | {:error, String.t()}
  def current_balance(address_or_addresses, slug) do
    with {:ok, {decimals, infr, blockchain}} <- info_by_slug(slug),
         {:ok, table} <- realtime_balances_table_or_nil(slug, infr) do
      addresses =
        address_or_addresses
        |> List.wrap()
        |> Sanbase.BlockchainAddress.to_internal_format()

      do_current_balance(addresses, slug, decimals, blockchain, table)
    end
  end

  def current_balance_top_addresses(slug, opts) do
    with {:ok, {decimals, infrastructure, blockchain}} <- info_by_slug(slug),
         {:ok, table} <- realtime_balances_table(slug, infrastructure) do
      query_struct = top_addresses_query(slug, decimals, blockchain, table, opts)

      ClickhouseRepo.query_transform(query_struct, fn [address, balance] ->
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

  def realtime_balances_table("ethereum", "ETH"),
    do: {:ok, "eth_balances_realtime"}

  def realtime_balances_table(_, "ETH"), do: {:ok, "erc20_balances_realtime"}

  def realtime_balances_table(slug, _infrastructure),
    do: {:error, "The slug #{slug} does not have support for realtime balances"}

  def supported_infrastructures(),
    do: ["ETH", "BTC", "BCH", "LTC", "BNB", "BEP2", "XRP"]

  # Private functions

  defp do_current_balance(addresses, slug, decimals, blockchain, table) do
    query_struct = current_balance_query(addresses, slug, decimals, blockchain, table)

    ClickhouseRepo.query_transform(query_struct, fn [address, balance] ->
      %{
        address: address,
        balance: balance
      }
    end)
  end

  defp do_balance_change(addresses, slug, decimals, blockchain, from, to) do
    query_struct = balance_change_query(addresses, slug, decimals, blockchain, from, to)

    ClickhouseRepo.query_transform(query_struct, fn
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
    query_struct =
      historical_balance_changes_query(
        addresses,
        slug,
        decimals,
        blockchain,
        from,
        to,
        interval
      )

    ClickhouseRepo.query_transform(query_struct, fn [unix, balance_change] ->
      %{
        datetime: DateTime.from_unix!(unix),
        balance_change_amount: balance_change
      }
    end)
  end

  defp do_last_balance_before(
         address_or_addresses,
         slug,
         decimals,
         blockchain,
         datetime
       ) do
    addresses =
      address_or_addresses
      |> List.wrap()
      |> Sanbase.BlockchainAddress.to_internal_format()

    query_struct = last_balance_before_query(addresses, slug, decimals, blockchain, datetime)

    case ClickhouseRepo.query_transform(query_struct, & &1) do
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
    query_struct =
      historical_balance_query(address, slug, decimals, blockchain, from, to, interval)

    ClickhouseRepo.query_transform(query_struct, fn [unix, value, has_changed] ->
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
    query_struct =
      historical_balance_ohlc_query(address, slug, decimals, blockchain, from, to, interval)

    ClickhouseRepo.query_transform(
      query_struct,
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

  defp info_by_slug(slug) do
    case Project.contract_info_infrastructure_by_slug(slug) do
      {:ok, _contract, decimals, infr} ->
        case Sanbase.BlockchainAddress.blockchain_from_infrastructure(infr) do
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

  defp hidden_projects_slugs() do
    {:ok, hidden_projects_slugs} =
      Sanbase.Cache.get_or_store(:hidden_projects_slugs, fn ->
        mapset = Sanbase.Project.List.hidden_projects_slugs() |> MapSet.new()

        {:ok, mapset}
      end)

    hidden_projects_slugs
  end
end
