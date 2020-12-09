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

  @spec add_labels(String.t(), list(input_transaction)) :: {:ok, list(output_transaction)}
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
    SELECT address,
           label,
           concat('\{', '"owner": "', owner, '"\}') as metadata
    FROM (
        SELECT address,
               arrayJoin(labels_owners_filtered) as label_owner,
               label_owner.1 as label_raw,
               label_owner.2 as owner,
               asset_id,
               multiIf(
                   owner = 'uniswap router', 'Uniswap Router',
                   label_raw='uniswap_ecosystem', 'Uniswap Ecosystem',
                   label_raw='cex_dex_trader', 'CEX & DEX Trader',
                   label_raw='centralized_exchange', 'CEX',
                   label_raw='decentralized_exchange', 'DEX',
                   label_raw='withdrawal', 'CEX Trader',
                   label_raw='dex_trader', 'DEX Trader',
                   label_raw='whale' AND asset_id = (SELECT asset_id FROM asset_metadata FINAL PREWHERE name = ?1), 'Whale',
                   label_raw='whale' AND asset_id != (SELECT asset_id FROM asset_metadata FINAL PREWHERE name = ?1), 'whale_wrong',
                   label_raw='deposit', 'CEX Deposit',
                   label_raw='defi', 'DeFi',
                   label_raw='deployer', 'Deployer',
                   label_raw='stablecoin', 'Stablecoin',
                   label_raw='uniswap_ecosystem', 'Uniswap',
                   label_raw='makerdao-cdp-owner', 'MakerDAO CDP Owner',
                   label_raw='makerdao-bite-keeper', 'MakerDAO Bite Keeper',
                   label_raw='genesis', 'Genesis',
                   label_raw='proxy', 'Proxy',
                   label_raw='system', 'System',
                   label_raw='miner', 'Miner',
                   label_raw='contract_factory', 'Contract Factory',
                   label_raw='derivative_token', 'Derivative Token',
                   label_raw='eth2stakingcontract', 'ETH2 Staking Contract',
                   label_raw
               ) as label
        FROM (
            SELECT address_hash,
                   address,
                   asset_id,
                   splitByChar(',', labels) as label_arr,
                   splitByChar(',', owners) as owner_arr,
                   arrayZip(label_arr, owner_arr) as labels_owners,
                   multiIf(
                       has(label_arr, 'system'), arrayFilter(x -> x.1 = 'system', labels_owners),
                       has(label_arr, 'centralized_exchange'), arrayFilter(x -> x.1 NOT IN ('deposit', 'withdrawal'), labels_owners),
                       has(label_arr, 'decentralized_exchange'), arrayFilter(x -> x.1 != 'dex_trader', labels_owners),
                       hasAll(label_arr, ['deposit', 'withdrawal']), arrayFilter(x -> x.1 != 'withdrawal', labels_owners),
                       hasAll(label_arr, ['dex_trader', 'withdrawal']), arrayPushFront(arrayFilter(x -> x.1 NOT IN ['dex_trader', 'withdrawal'], labels_owners), ('cex_dex_trader', arrayFilter(x -> x.1 == 'withdrawal', labels_owners)[1].2)),
                       labels_owners
                   ) as labels_owners_filtered
            FROM eth_labels_final
            ANY INNER JOIN (
                SELECT cityHash64(address) as address_hash,
                       address
                FROM (
                    SELECT lower(arrayJoin([?2])) as address
                )
            )
            USING address_hash
            PREWHERE address_hash IN (
                SELECT cityHash64(address)
                FROM (
                    SELECT lower(arrayJoin([?2])) as address
                )
            )
        )
    )
    WHERE label != 'whale_wrong'
    """

    {query, [slug, addresses]}
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

  defp do_add_labels(_slug, transactions, address_labels_map) do
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
