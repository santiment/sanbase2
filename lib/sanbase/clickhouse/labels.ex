defmodule Sanbase.Clickhouse.Label do
  @moduledoc """
  Labeling transaction addresses
  """

  @type label :: %{
          name: String.t(),
          metadata: String.t()
        }

  @type input_transaction :: %{
          from_address: %{
            address: String.t(),
            is_exhange: boolean
          },
          to_address: %{
            address: String.t(),
            is_exhange: boolean
          },
          trx_value: float,
          trx_hash: String,
          datetime: Datetime.t()
        }

  @type output_transaction :: %{
          from_address: %{
            address: String.t(),
            is_exhange: boolean,
            labels: list(label)
          },
          to_address: %{
            address: String.t(),
            is_exhange: boolean,
            labels: list(label)
          },
          trx_value: float,
          trx_hash: String,
          datetime: Datetime.t()
        }

  @spec add_labels(list(input_transaction)) :: {:ok, list(output_transaction)}
  def add_labels([]), do: {:ok, []}

  def add_labels(transactions) when is_list(transactions) do
    add_labels(nil, transactions)
  end

  @spec add_labels(String.t() | nil, list(input_transaction)) :: {:ok, list(output_transaction)}
  def add_labels(_, []), do: {:ok, []}

  def add_labels(slug, transactions) when is_list(transactions) do
    addresses = get_list_of_addresses(transactions)
    {query, args} = addresses_labels_query(slug, addresses)

    Sanbase.ClickhouseRepo.query_reduce(query, args, %{}, fn [address, label, metadata], acc ->
      label = %{name: label, metadata: metadata}
      Map.update(acc, address, [label], &[label | &1])
    end)
    |> case do
      {:ok, address_labels_map} ->
        {:ok, do_add_labels(slug, transactions, address_labels_map)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_address_labels(slug, addresses) when is_list(addresses) do
    {query, args} = addresses_labels_query(slug, addresses)

    Sanbase.ClickhouseRepo.query_reduce(query, args, %{}, fn [address, label, metadata], acc ->
      label = %{name: label, metadata: metadata}
      Map.update(acc, address, [label], &[label | &1])
    end)
  end

  # helpers
  defp addresses_labels_query(nil, addresses) do
    query = """
    SELECT lower(address) as address,
           #{labels_human_readable_aliases_sql_part()},
           metadata
    FROM blockchain_address_labels FINAL
    PREWHERE
      blockchain = 'ethereum' AND
      lower(address) IN (?1) AND
      #{not_whale_not_asset_filter()}
    HAVING (sign = 1) AND #{not_system_address()}
    """

    {query, [addresses]}
  end

  defp addresses_labels_query("bitcoin", addresses) do
    query = """
    SELECT address, label, metadata
    FROM blockchain_address_labels FINAL
    PREWHERE blockchain = 'bitcoin' AND address IN (?1)
    HAVING sign = 1
    """

    {query, [addresses]}
  end

  defp addresses_labels_query(slug, addresses) do
    query = """
    SELECT lower(address) as address,
           #{labels_human_readable_aliases_sql_part()},
           metadata
    FROM blockchain_address_labels FINAL
    PREWHERE
      blockchain = 'ethereum' AND
      lower(address) IN (?1) AND
      (#{whale_and_asset_filter(position: 2)} OR #{not_whale_not_asset_filter()})
      HAVING (sign = 1) AND #{not_system_address()}
    """

    {query, [addresses, slug]}
  end

  defp not_whale_not_asset_filter do
    "(label != 'whale' and asset_id = 0)"
  end

  defp whale_and_asset_filter(position) do
    position_number = Keyword.fetch!(position, :position)

    """
    (label = 'whale' AND
      asset_id = (SELECT argMax(asset_id, computed_at) FROM asset_metadata FINAL PREWHERE name = ?#{
      position_number
    }))
    """
  end

  defp not_system_address do
    "(address NOT IN ('0x0000000000000000000000000000000000000000', 'burn', 'mint') OR label = 'System')"
  end

  defp labels_human_readable_aliases_sql_part() do
    """
      multiIf(label='uniswap_ecosystem', 'Uniswap Ecosystem',
      label='centralized_exchange', 'CEX',
      label='decentralized_exchange', 'DEX',
      label='withdrawal', 'CEX Trader',
      label='dex_trader', 'DEX Trader',
      label='whale', 'Whale',
      label='deposit', 'CEX Deposit',
      label='defi', 'DeFi',
      label='deployer', 'Deployer',
      label='stablecoin', 'Stablecoin',
      label='uniswap_ecosystem', 'Uniswap',
      label='makerdao-cdp-owner', 'MakerDAO CDP Owner',
      label='makerdao-bite-keeper', 'MakerDAO Bite Keeper',
      label='genesis', 'Genesis',
      label='proxy', 'Proxy',
      label='system', 'System',
      label='miner', 'Miner', label) as label
    """
  end

  defp get_list_of_addresses(transactions) do
    transactions
    |> Enum.flat_map(fn transaction ->
      [
        transaction.from_address && transaction.from_address.address,
        transaction.to_address.address
      ]
    end)
    |> Enum.uniq()
    |> Enum.reject(&is_nil/1)
  end

  defp do_add_labels("bitcoin", transactions, address_labels_map) do
    transactions
    |> Enum.map(fn %{to_address: to} = transaction ->
      to_labels = Map.get(address_labels_map, to.address, [])
      to = Map.put(to, :labels, to_labels)

      %{transaction | to_address: to}
    end)
  end

  defp do_add_labels(nil, transactions, address_labels_map) do
    do_add_labels(transactions, address_labels_map)
  end

  defp do_add_labels(_slug, transactions, address_labels_map) do
    do_add_labels(transactions, address_labels_map)
  end

  defp do_add_labels(transactions, address_labels_map) do
    transactions
    |> Enum.map(fn %{from_address: from, to_address: to} = transaction ->
      from_labels = Map.get(address_labels_map, String.downcase(from.address), [])
      from = Map.put(from, :labels, from_labels)

      to_labels = Map.get(address_labels_map, String.downcase(to.address), [])
      to = Map.put(to, :labels, to_labels)

      %{transaction | from_address: from, to_address: to}
    end)
  end
end
