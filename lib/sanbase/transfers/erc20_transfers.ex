defmodule Sanbase.Transfers.Erc20Transfers do
  @moduledoc ~s"""
  Uses ClickHouse to work with ERC20 transfers.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{
          datetime: %DateTime{},
          contract: String.t(),
          from_address: String.t(),
          to_address: String.t(),
          trx_hash: String.t(),
          trx_value: float,
          block_number: non_neg_integer,
          trx_position: non_neg_integer,
          log_index: non_neg_integer,
          project: map()
        }

  import Sanbase.Utils.Transform

  alias Sanbase.ClickhouseRepo
  alias Sanbase.Model.Project

  require Sanbase.Utils.Config, as: Config
  defp dt_ordered_table(), do: Config.get(:dt_ordered_table)

  @eth_decimals 1_000_000_000_000_000_000

  # Note: The schema name is not important as it is not used.
  @primary_key false
  @timestamps_opts [updated_at: false]
  schema "erc20_transfers" do
    field(:datetime, :utc_datetime, source: :dt)
    field(:contract, :string, primary_key: true)
    field(:from_address, :string, primary_key: true, source: :from)
    field(:to_address, :string, primary_key: true, source: :to)
    field(:trx_hash, :string, source: :transactionHash)
    field(:trx_value, :float, source: :value)
    field(:block_number, :integer, source: :blockNumber)
    field(:trx_position, :integer, source: :transactionPosition)
    field(:log_index, :integer, source: :logIndex)
    field(:project, :map)
  end

  @spec changeset(any(), any()) :: no_return()
  def changeset(_, _) do
    raise "Should not try to change eth daily active addresses"
  end

  @spec top_wallet_transfers(
          String.t(),
          list(String.t()),
          DateTime.t(),
          DateTime.t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          String.t()
        ) ::
          {:ok, list(map())} | {:error, String.t()}
  def top_wallet_transfers(_contract, [], _from, _to, _page, _page_size, _type), do: {:ok, []}

  def top_wallet_transfers(contract, wallets, from, to, decimals, page, page_size, type) do
    {query, args} =
      top_wallet_transfers_query(contract, wallets, from, to, decimals, page, page_size, type)

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
          non_neg_integer(),
          non_neg_integer(),
          list(String.t())
        ) ::
          {:ok, list(t)} | {:error, String.t()}
  def top_transfers(contract, from, to, decimals, page, page_size, excluded_addresses \\ []) do
    decimals = Sanbase.Math.ipow(10, decimals)

    {query, args} =
      top_transfers_query(
        contract,
        from,
        to,
        page,
        page_size,
        decimals,
        excluded_addresses
      )

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

  def transaction_volume_per_address(addresses, contract, from, to, decimals \\ 0) do
    query = """
    SELECT
      address,
      SUM(incoming) AS incoming,
      SUM(outgoing) AS outgoing
    FROM (
      SELECT
        from AS address,
        0 AS incoming,
        value AS outgoing
      FROM #{dt_ordered_table()} FINAL
      PREWHERE
        from IN (?1) AND
        assetRefId = cityHash64('ETH_' || ?2) AND
        dt >= toDateTime(?3) AND
        dt < toDateTime(?4)

      UNION ALL

      SELECT
        to AS address,
        value AS incoming,
        0 AS outgoing
      FROM #{dt_ordered_table()} FINAL
      PREWHERE
        to in (?1) AND
        assetRefId = cityHash64('ETH_' || ?2) AND
        dt >= toDateTime(?3) AND
        dt < toDateTime(?4)
    )
    GROUP BY address
    """

    decimals = Sanbase.Math.ipow(10, decimals)
    addresses = Enum.map(addresses, &String.downcase/1)
    args = [addresses, contract, DateTime.to_unix(from), DateTime.to_unix(to)]

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [address, incoming, outgoing] ->
        incoming = incoming / decimals
        outgoing = outgoing / decimals

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
          {:ok, nil} | {:ok, list(t)} | {:error, String.t()}
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

  # Private functions

  defp top_wallet_transfers_query(wallets, contract, from, to, decimals, page, page_size, type) do
    query = """
    SELECT
      toUnixTimestamp(dt),
      from,
      to,
      transactionHash,
      value / ?7
    FROM erc20_transfers FINAL
    PREWHERE
    #{top_wallet_transfers_address_clause(type, arg_position: 1, trailing_and: true)}
      assetRefId = cityHash64('ETH_' || ?2) AND
      dt >= toDateTime(?3) AND
      dt <= toDateTime(?4) AND
      type = 'call'
    ORDER BY value DESC
    LIMIT ?5 OFFSET ?6
    """

    offset = (page - 1) * page_size

    args = [
      wallets,
      contract,
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix(),
      page_size,
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

  defp top_transfers_query(contract, from, to, page, page_size, decimals, excluded_addresses) do
    query = """
    SELECT
      toUnixTimestamp(dt) AS datetime,
      from,
      to,
      transactionHash,
      value / ?1
    FROM #{dt_ordered_table()} FINAL
    PREWHERE
      assetRefId = cityHash64('ETH_' || ?2) AND
      dt >= toDateTime(?3) AND
      dt <= toDateTime(?4)
      #{maybe_exclude_addresses(excluded_addresses, arg_position: 7)}
    ORDER BY value DESC
    LIMIT ?5 OFFSET ?6
    """

    offset = (page - 1) * page_size
    maybe_extra_params = if excluded_addresses == [], do: [], else: [excluded_addresses]

    args =
      [
        decimals,
        contract,
        from |> DateTime.to_unix(),
        to |> DateTime.to_unix(),
        page_size,
        offset
      ] ++ maybe_extra_params

    {query, args}
  end

  defp recent_transactions_query(address, opts) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 10)
    only_sender = Keyword.get(opts, :only_sender, false)
    offset = (page - 1) * page_size

    query = """
    SELECT
      toUnixTimestamp(dt) AS datetime,
      from,
      to,
      transactionHash,
      value,
      name,
      decimals
    FROM erc20_transfers FINAL
    INNER JOIN (
      SELECT asset_ref_id AS assetRefId, name, decimals
      FROM asset_metadata FINAL
    ) USING (assetRefId)
    PREWHERE
      #{if only_sender, do: "from = ?1", else: "(from = ?1 OR to = ?1)"}
    ORDER BY dt DESC
    LIMIT ?2 OFFSET ?3
    """

    args = [String.downcase(address), page_size, offset]

    {query, args}
  end

  defp maybe_exclude_addresses([], _opts), do: ""

  defp maybe_exclude_addresses([_ | _], opts) do
    arg_position = Keyword.get(opts, :arg_position)

    "AND (from NOT IN (?#{arg_position}) AND to NOT IN (?#{arg_position}))"
  end

  defp decimals(decimals) when is_integer(decimals) and decimals > 0 do
    Sanbase.Math.ipow(10, decimals)
  end

  defp decimals(_), do: @eth_decimals

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
end
