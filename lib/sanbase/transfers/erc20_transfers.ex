defmodule Sanbase.Transfers.Erc20Transfers do
  @moduledoc ~s"""
  Uses ClickHouse to work with ERC20 transfers.
  """

  import Sanbase.Utils.Transform

  alias Sanbase.ClickhouseRepo
  alias Sanbase.Model.Project

  require Sanbase.Utils.Config, as: Config
  defp dt_ordered_table(), do: Config.get(:dt_ordered_table)

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
    {query, args} = top_wallet_transfers_query(wallets, contract, from, to, decimals, type, opts)

    ClickhouseRepo.query_transform(query, args, fn
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
    {query, args} = top_transfers_query(contract, from, to, decimals, excluded_addresses, opts)

    ClickhouseRepo.query_transform(
      query,
      args,
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
    {query, args} =
      blockchain_address_transaction_volume_over_time_query(
        addresses,
        contract,
        decimals,
        from,
        to,
        interval
      )

    ClickhouseRepo.query_transform(
      query,
      args,
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
    {query, args} =
      blockchain_address_transaction_volume_query(addresses, contract, decimals, from, to)

    ClickhouseRepo.query_transform(
      query,
      args,
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
    {query, args} = recent_transactions_query(address, opts)

    ClickhouseRepo.query_transform(query, args, fn
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
    {query, args} = transfers_summary_query(type, address, contract, decimals, from, to, opts)

    ClickhouseRepo.query_transform(
      query,
      args,
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

  # assetRefId, from, to, dt, transactionHash, logIndex, primaryKey
  defp top_wallet_transfers_query(wallets, contract, from, to, decimals, type, opts) do
    query = """
    SELECT
      toUnixTimestamp(dt),
      from,
      to,
      transactionHash,
      any(value) / ?7
    FROM erc20_transfers
    PREWHERE
      #{top_wallet_transfers_address_clause(type, arg_position: 1, trailing_and: true)}
      assetRefId = cityHash64('ETH_' || ?2) AND
      dt >= toDateTime(?3) AND
      dt < toDateTime(?4)
    GROUP BY assetRefId, from, to, dt, transactionHash, logIndex, primaryKey
    ORDER BY value DESC
    LIMIT ?5 OFFSET ?6
    """

    {limit, offset} = opts_to_limit_offset(opts)

    args = [
      wallets,
      contract,
      DateTime.to_unix(from),
      DateTime.to_unix(to),
      limit,
      offset,
      Sanbase.Math.ipow(10, decimals)
    ]

    {query, args}
  end

  defp top_wallet_transfers_address_clause(:in, opts) do
    arg_position = Keyword.fetch!(opts, :arg_position)
    trailing_and = Keyword.fetch!(opts, :trailing_and)

    str = "from NOT IN (?#{arg_position}) AND to IN (?#{arg_position})"
    if trailing_and, do: str <> " AND", else: str
  end

  defp top_wallet_transfers_address_clause(:out, opts) do
    arg_position = Keyword.fetch!(opts, :arg_position)
    trailing_and = Keyword.fetch!(opts, :trailing_and)

    str = "from IN (?#{arg_position}) AND to NOT IN (?#{arg_position})"
    if trailing_and, do: str <> " AND", else: str
  end

  defp top_wallet_transfers_address_clause(:all, opts) do
    arg_position = Keyword.fetch!(opts, :arg_position)
    trailing_and = Keyword.fetch!(opts, :trailing_and)

    str = """
    (
      (from IN (?#{arg_position}) AND NOT to IN (?#{arg_position})) OR
      (NOT from IN (?#{arg_position}) AND to IN (?#{arg_position}))
    )
    """

    if trailing_and, do: str <> " AND", else: str
  end

  defp top_transfers_query(contract, from, to, decimals, excluded_addresses, opts) do
    query = """
    SELECT
      toUnixTimestamp(dt) AS datetime,
      from,
      to,
      transactionHash,
      any(value) / ?1
    FROM #{dt_ordered_table()}
    PREWHERE
      assetRefId = cityHash64('ETH_' || ?2) AND
      dt >= toDateTime(?3) AND
      dt < toDateTime(?4)
      #{maybe_exclude_addresses(excluded_addresses, arg_position: 7)}
    GROUP BY assetRefId, from, to, value, dt, transactionHash
    ORDER BY value DESC
    LIMIT ?5 OFFSET ?6
    """

    {limit, offset} = opts_to_limit_offset(opts)

    maybe_extra_params = if excluded_addresses == [], do: [], else: [excluded_addresses]

    args =
      [
        Sanbase.Math.ipow(10, decimals),
        contract,
        DateTime.to_unix(from),
        DateTime.to_unix(to),
        limit,
        offset
      ] ++ maybe_extra_params

    {query, args}
  end

  defp recent_transactions_query(address, opts) do
    {limit, offset} = opts_to_limit_offset(opts)
    only_sender = Keyword.get(opts, :only_sender, false)

    query = """
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
      FROM erc20_transfers
      PREWHERE #{if only_sender, do: "from = ?1", else: "(from = ?1 OR to = ?1)"}
      GROUP BY assetRefId, from, to, dt, transactionHash, logIndex, primaryKey
    )
    INNER JOIN (
      SELECT asset_ref_id AS assetRefId, name, decimals
      FROM asset_metadata FINAL
    ) USING (assetRefId)
    ORDER BY dt DESC
    LIMIT ?2 OFFSET ?3
    """

    args = [String.downcase(address), limit, offset]

    {query, args}
  end

  defp maybe_exclude_addresses([], _opts), do: ""

  defp maybe_exclude_addresses([_ | _], opts) do
    arg_position = Keyword.get(opts, :arg_position)

    "AND (from NOT IN (?#{arg_position}) AND to NOT IN (?#{arg_position}))"
  end

  defp decimals(decimals) when is_integer(decimals) and decimals >= 0 do
    Sanbase.Math.ipow(10, decimals)
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
    query = """
    WITH ( pow(10, ?3) ) AS expanded_decimals
    SELECT
      address,
      SUM(incoming) / expanded_decimals AS incoming,
      SUM(outgoing) / expanded_decimals AS outgoing
    FROM (
      SELECT
        from AS address,
        0 AS incoming,
        any(value) AS outgoing
      FROM erc20_transfers
      PREWHERE
        from IN (?1) AND
        assetRefId = cityHash64('ETH_' || ?2) AND
        dt >= toDateTime(?4) AND
        dt < toDateTime(?5)
      GROUP BY assetRefId, from, to, dt, transactionHash, logIndex, primaryKey

      UNION ALL

      SELECT
        to AS address,
        any(value) AS incoming,
        0 AS outgoing
      FROM erc20_transfers_to
      PREWHERE
        to in (?1) AND
        assetRefId = cityHash64('ETH_' || ?2) AND
        dt >= toDateTime(?4) AND
        dt < toDateTime(?5)
      GROUP BY assetRefId, from, to, dt, transactionHash, logIndex, primaryKey
    )
    GROUP BY address
    """

    args = [
      addresses,
      contract,
      decimals,
      DateTime.to_unix(from),
      DateTime.to_unix(to)
    ]

    {query, args}
  end

  defp blockchain_address_transaction_volume_over_time_query(
         addresses,
         contract,
         decimals,
         from,
         to,
         interval
       ) do
    query = """
    WITH ( pow(10, ?4) ) AS expanded_decimals
    SELECT
      toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time,
      SUM(incoming) / expanded_decimals AS incoming,
      SUM(outgoing) / expanded_decimals AS outgoing
    FROM (
      SELECT
        dt,
        0 AS incoming,
        any(value) AS outgoing
      FROM erc20_transfers
      PREWHERE
        from IN (?2) AND
        assetRefId = cityHash64('ETH_' || ?3) AND
        dt >= toDateTime(?5) AND
        dt < toDateTime(?6)
      GROUP BY assetRefId, from, to, dt, transactionHash, logIndex, primaryKey

      UNION ALL

      SELECT
        dt,
        any(value) AS incoming,
        0 AS outgoing
      FROM erc20_transfers_to
      PREWHERE
        to in (?2) AND
        assetRefId = cityHash64('ETH_' || ?3) AND
        dt >= toDateTime(?5) AND
        dt < toDateTime(?6)
      GROUP BY assetRefId, from, to, dt, transactionHash, logIndex, primaryKey
    )
    GROUP BY time
    """

    from = DateTime.to_unix(from)
    to = DateTime.to_unix(to)
    interval_sec = Sanbase.DateTimeUtils.str_to_sec(interval)
    args = [interval_sec, addresses, contract, decimals, from, to]

    {query, args}
  end

  defp transfers_summary_query(type, address, contract, decimals, from, to, opts) do
    order_by_str =
      case Keyword.get(opts, :order_by, :transaction_volume) do
        :transaction_volume -> "transaction_volume"
        :transfers_count -> "transfers_count"
      end

    {limit, offset} = opts_to_limit_offset(opts)

    {select_column, filter_column, table} =
      case type do
        :incoming -> {"from", "to", "erc20_transfers_to"}
        :outgoing -> {"to", "from", "erc20_transfers"}
      end

    query = """
    SELECT
      toUnixTimestamp(max(dt)) AS last_transfer_datetime,
      "#{select_column}" AS address,
      SUM(value) / ?1 AS transaction_volume,
      COUNT(*) AS transfers_count
    FROM (
      SELECT dt, from, to, any(value) AS value
      FROM #{table}
      assetRefId = cityHash64('ETH_' || ?2) AND
      #{filter_column} = ?3 AND
      dt >= toDateTime(?4) AND
      dt < toDateTime(?5)
      GROUP BY assetRefId, from, to, dt, transactionHash, logIndex, primaryKey
    )
    GROUP BY "#{select_column}"
    ORDER BY #{order_by_str} DESC
    LIMIT ?6 OFFSET ?7
    """

    args = [Sanbase.Math.ipow(10, decimals), contract, address, from, to, limit, offset]

    {query, args}
  end
end
