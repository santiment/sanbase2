defmodule Sanbase.Transfers.Erc20Transfers do
  @moduledoc ~s"""
  Uses ClickHouse to work with ERC20 transfers.
  """

  import Sanbase.Utils.Transform
  import Sanbase.Transfers.Utils, only: [top_wallet_transfers_address_clause: 2]

  alias Sanbase.ClickhouseRepo
  alias Sanbase.Project

  defguard is_non_neg_integer(int) when is_integer(int) and int > 0

  @spec top_wallet_transfers(
          list(String.t()),
          String.t(),
          DateTime.t(),
          DateTime.t(),
          non_neg_integer(),
          pos_integer(),
          pos_integer(),
          :all | :in | :out
        ) ::
          {:ok, list(map())} | {:error, String.t()}
  def top_wallet_transfers([], _contract, _from, _to, _page, _page_size, _type), do: {:ok, []}

  def top_wallet_transfers(wallets, contract, from, to, decimals, page, page_size, type)
      when is_non_neg_integer(page) and is_non_neg_integer(page_size) do
    opts = [page: page, page_size: page_size]
    query_struct = top_wallet_transfers_query(wallets, contract, from, to, decimals, type, opts)

    ClickhouseRepo.query_transform(query_struct, fn
      [timestamp, from_address, to_address, trx_hash, trx_value] ->
        %{
          datetime: DateTime.from_unix!(timestamp),
          from_address: maybe_transform_from_address(from_address),
          to_address: maybe_transform_to_address(to_address),
          trx_hash: trx_hash,
          trx_value: trx_value
        }
    end)
  end

  @doc ~s"""
  Return the `limit` biggest transaction for a given contract and time period.
  If the top transactions for SAN token are needed, the SAN contract address must be
  provided as a first argument.
  """
  @spec top_transfers(
          String.t(),
          %DateTime{},
          %DateTime{},
          non_neg_integer(),
          pos_integer(),
          pos_integer(),
          list(String.t())
        ) ::
          {:ok, list(map())} | {:error, String.t()}
  def top_transfers(contract, from, to, decimals, page, page_size, excluded_addresses \\ [])
      when is_non_neg_integer(page) and is_non_neg_integer(page_size) do
    opts = [page: page, page_size: page_size]
    query_struct = top_transfers_query(contract, from, to, decimals, excluded_addresses, opts)

    ClickhouseRepo.query_transform(
      query_struct,
      fn [datetime, from_address, to_address, trx_hash, trx_value] ->
        %{
          datetime: DateTime.from_unix!(datetime),
          from_address: maybe_transform_from_address(from_address),
          to_address: maybe_transform_to_address(to_address),
          trx_hash: trx_hash,
          trx_value: trx_value
        }
      end
    )
  end

  def blockchain_address_transaction_volume_over_time(
        addresses,
        contract,
        decimals,
        from,
        to,
        interval
      ) do
    query_struct =
      blockchain_address_transaction_volume_over_time_query(
        addresses,
        contract,
        decimals,
        from,
        to,
        interval
      )

    ClickhouseRepo.query_transform(
      query_struct,
      fn [unix, incoming, outgoing] ->
        %{
          datetime: DateTime.from_unix!(unix),
          transaction_volume_inflow: incoming,
          transaction_volume_outflow: outgoing,
          transaction_volume_total: incoming + outgoing
        }
      end
    )
  end

  def blockchain_address_transaction_volume(addresses, contract, decimals, from, to) do
    query_struct =
      blockchain_address_transaction_volume_query(addresses, contract, decimals, from, to)

    ClickhouseRepo.query_transform(
      query_struct,
      fn [address, incoming, outgoing] ->
        %{
          address: address,
          transaction_volume_inflow: incoming,
          transaction_volume_outflow: outgoing,
          transaction_volume_total: incoming + outgoing
        }
      end
    )
    |> maybe_apply_function(fn data ->
      Enum.sort_by(data, & &1.transaction_volume_total, :desc)
    end)
  end

  @spec recent_transactions(String.t(),
          page: non_neg_integer(),
          page_size: non_neg_integer(),
          only_sender: boolean()
        ) ::
          {:ok, list(map())} | {:error, String.t()}
  def recent_transactions(address, opts) do
    query_struct = recent_transactions_query(address, opts)

    ClickhouseRepo.query_transform(query_struct, fn
      [timestamp, from_address, to_address, trx_hash, trx_value, name, decimals] ->
        %{
          datetime: DateTime.from_unix!(timestamp),
          from_address: from_address,
          to_address: to_address,
          project: name,
          trx_hash: trx_hash,
          trx_value: trx_value / decimals(decimals)
        }
    end)
    |> maybe_transform()
  end

  def incoming_transfers_summary(address, contract, decimals, from, to, opts) do
    execute_transfers_summary_query(:incoming, address, contract, decimals, from, to, opts)
  end

  def outgoing_transfers_summary(address, contract, decimals, from, to, opts) do
    execute_transfers_summary_query(:outgoing, address, contract, decimals, from, to, opts)
  end

  # Private functions

  defp execute_transfers_summary_query(type, address, contract, decimals, from, to, opts) do
    query_struct = transfers_summary_query(type, address, contract, decimals, from, to, opts)

    ClickhouseRepo.query_transform(
      query_struct,
      fn [last_transfer_datetime, address, transaction_volume, transfers_count] ->
        %{
          last_transfer_datetime: DateTime.from_unix!(last_transfer_datetime),
          address: address,
          transaction_volume: transaction_volume,
          transfers_count: transfers_count
        }
      end
    )
  end

  defp top_wallet_transfers_query(wallets, contract, from, to, decimals, type, opts) do
    sql = """
    SELECT
      toUnixTimestamp(dt),
      from,
      to,
      transactionHash,
      (any(value) / {{decimals}}) AS value
    FROM erc20_transfers
    WHERE
      #{top_wallet_transfers_address_clause(type, argument_name: "wallets", trailing_and: true)}
      assetRefId = cityHash64('ETH_' || {{contract}}) AND
      dt >= toDateTime({{from}}) AND
      dt < toDateTime({{to}})
    GROUP BY assetRefId, from, to, dt, transactionHash, logIndex, primaryKey
    ORDER BY value DESC
    LIMIT {{limit}} OFFSET {{offset}}
    """

    {limit, offset} = opts_to_limit_offset(opts)

    params = %{
      wallets: wallets,
      contract: contract,
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to),
      limit: limit,
      offset: offset,
      decimals: Integer.pow(10, decimals)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp top_transfers_query(contract, from, to, decimals, excluded_addresses, opts) do
    sql = """
    SELECT
      toUnixTimestamp(dt) AS datetime,
      from,
      to,
      transactionHash,
      (any(value) / {{decimals}}) AS value
    FROM erc20_transfers
    WHERE
      assetRefId = cityHash64('ETH_' || {{contract}}) AND
      dt >= toDateTime({{from}}) AND
      dt < toDateTime({{to}})
      #{maybe_exclude_addresses(excluded_addresses, argument_name: "excluded_addresses")}
    GROUP BY assetRefId, from, to, dt, transactionHash
    ORDER BY value DESC
    LIMIT {{limit}} OFFSET {{offset}}
    """

    {limit, offset} = opts_to_limit_offset(opts)

    params = %{
      decimals: Integer.pow(10, decimals),
      contract: contract,
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to),
      limit: limit,
      offset: offset,
      excluded_addresses: excluded_addresses
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp recent_transactions_query(address, opts) do
    only_sender = Keyword.get(opts, :only_sender, false)

    maybe_union_with_to_table =
      case only_sender do
        true ->
          ""

        false ->
          """
          UNION DISTINCT
          SELECT * FROM erc20_transfers_to WHERE to = {{address}}
          """
      end

    sql = """
    SELECT
      toUnixTimestamp(dt) AS datetime,
      from,
      to,
      transactionHash,
      value,
      name,
      decimals
    FROM (
      SELECT assetRefId, from, to, dt, transactionHash, any(value) AS value
      FROM (
        SELECT * FROM erc20_transfers WHERE from = {{address}}
        #{maybe_union_with_to_table}
      )
      GROUP BY assetRefId, from, to, dt, transactionHash, logIndex, primaryKey
    )
    INNER JOIN (
      SELECT asset_ref_id AS assetRefId, name, decimals
      FROM asset_metadata FINAL
    ) USING (assetRefId)
    ORDER BY dt DESC
    LIMIT {{limit}} OFFSET {{offset}}
    """

    {limit, offset} = opts_to_limit_offset(opts)

    params = %{
      address: Sanbase.BlockchainAddress.to_internal_format(address),
      limit: limit,
      offset: offset
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp maybe_exclude_addresses([], _opts), do: ""

  defp maybe_exclude_addresses([_ | _], opts) do
    arg_name = Keyword.get(opts, :argument_name)

    "AND (from NOT IN ({{#{arg_name}}}) AND to NOT IN ({{#{arg_name}}}))"
  end

  defp decimals(decimals) when is_integer(decimals) and decimals >= 0 do
    Integer.pow(10, decimals)
  end

  defp maybe_transform({:ok, data}) do
    slugs = data |> Enum.map(& &1.project)

    slug_project_map =
      Project.by_slug(slugs)
      |> Enum.into(%{}, fn project -> {project.slug, project} end)

    data =
      Enum.map(data, fn %{project: slug} = trx ->
        %{trx | project: Map.get(slug_project_map, slug, nil)}
      end)

    {:ok, data}
  end

  defp maybe_transform({:error, _} = result), do: result

  defp blockchain_address_transaction_volume_query(
         addresses,
         contract,
         decimals,
         from,
         to
       ) do
    sql = """
    SELECT
      address,
      SUM(incoming) / {{decimals}} AS incoming,
      SUM(outgoing) / {{decimals}} AS outgoing
    FROM (
      SELECT
        from AS address,
        0 AS incoming,
        any(value) AS outgoing
      FROM erc20_transfers
      WHERE
        from IN ({{addresses}}) AND
        assetRefId = cityHash64('ETH_' || {{contract}}) AND
        dt >= toDateTime({{from}}) AND
        dt < toDateTime({{to}})
      GROUP BY assetRefId, from, to, dt, transactionHash, logIndex, primaryKey

      UNION ALL

      SELECT
        to AS address,
        any(value) AS incoming,
        0 AS outgoing
      FROM erc20_transfers_to
      WHERE
        to IN ({{from}}) AND
        assetRefId = cityHash64('ETH_' || {{contract}}) AND
        dt >= toDateTime({{from}}) AND
        dt < toDateTime({{to}})
      GROUP BY assetRefId, from, to, dt, transactionHash, logIndex, primaryKey
    )
    GROUP BY address
    """

    params = %{
      addresses: addresses,
      contract: contract,
      decimals: Integer.pow(10, decimals),
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp blockchain_address_transaction_volume_over_time_query(
         addresses,
         contract,
         decimals,
         from,
         to,
         interval
       ) do
    sql = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(dt), {{interval}}) * {{interval}}) AS time,
      SUM(incoming) / {{decimals}} AS incoming,
      SUM(outgoing) / {{decimals}} AS outgoing
    FROM (
      SELECT
        dt,
        0 AS incoming,
        any(value) AS outgoing
      FROM erc20_transfers
      WHERE
        from IN ({{addresses}}) AND
        assetRefId = cityHash64('ETH_' || {{contract}}) AND
        dt >= toDateTime({{from}}) AND
        dt < toDateTime({{to}})
      GROUP BY assetRefId, from, to, dt, transactionHash, logIndex, primaryKey

      UNION ALL

      SELECT
        dt,
        any(value) AS incoming,
        0 AS outgoing
      FROM erc20_transfers_to
      WHERE
        to in ({{addresses}}) AND
        assetRefId = cityHash64('ETH_' || {{contract}}) AND
        dt >= toDateTime({{from}}) AND
        dt < toDateTime({{to}})
      GROUP BY assetRefId, from, to, dt, transactionHash, logIndex, primaryKey
    )
    GROUP BY time
    """

    params = %{
      interval: Sanbase.DateTimeUtils.str_to_sec(interval),
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to),
      addresses: addresses,
      contract: contract,
      decimals: Integer.pow(10, decimals)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp transfers_summary_query(type, address, contract, decimals, from, to, opts) do
    order_by_str =
      case Keyword.get(opts, :order_by, :transaction_volume) do
        :transaction_volume -> "transaction_volume"
        :transfers_count -> "transfers_count"
      end

    {select_column, filter_column, table} =
      case type do
        :incoming -> {"from", "to", "erc20_transfers_to"}
        :outgoing -> {"to", "from", "erc20_transfers"}
      end

    sql = """
    SELECT
      toUnixTimestamp(max(dt)) AS last_transfer_datetime,
      "#{select_column}" AS address,
      SUM(value) / {{decimals}} AS transaction_volume,
      COUNT(*) AS transfers_count
    FROM (
      SELECT dt, from, to, any(value) AS value
      FROM #{table}
      WHERE
        assetRefId = cityHash64('ETH_' || {{contract}}) AND
        #{filter_column} = {{address}} AND
        dt >= toDateTime({{from}}) AND
        dt < toDateTime({{to}})
      GROUP BY assetRefId, from, to, dt, transactionHash, logIndex, primaryKey
    )
    GROUP BY "#{select_column}"
    ORDER BY #{order_by_str} DESC
    LIMIT {{limit}} OFFSET {{offset}}
    """

    {limit, offset} = opts_to_limit_offset(opts)

    params = %{
      decimals: Integer.pow(10, decimals),
      contract: contract,
      address: address,
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to),
      limit: limit,
      offset: offset
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end
end
