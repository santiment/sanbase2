defmodule Sanbase.Clickhouse.Label do
  @moduledoc """
  Labeling addresses
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

  def list_all(:all = _blockchain) do
    query = """
    SELECT DISTINCT(label) FROM blockchain_address_labels
    """

    Sanbase.ClickhouseRepo.query_transform(query, [], fn [label] -> label end)
  end

  def list_all(blockchain) do
    query = """
    SELECT DISTINCT(label) FROM blockchain_address_labels PREWHERE blockchain = ?1
    """

    Sanbase.ClickhouseRepo.query_transform(query, [blockchain], fn [label] -> label end)
  end

  @spec add_labels(String.t() | nil, list(input_transaction)) :: {:ok, list(output_transaction)}
  def add_labels(_, []), do: {:ok, []}

  def add_labels(slug, transactions) when is_list(transactions) do
    addresses = get_list_of_addresses(transactions)
    {query, args} = addresses_labels_query(slug, addresses)

    Sanbase.ClickhouseRepo.query_reduce(query, args, %{}, fn [address, label, metadata], acc ->
      label = %{name: label, metadata: metadata, origin: "santiment"}
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
      label = %{name: label, metadata: metadata, origin: "santiment"}
      Map.update(acc, address, [label], &[label | &1])
    end)
  end

  # helpers

  def addresses_labels_query("bitcoin", addresses) do
    query = """
    SELECT address, label, metadata
    FROM blockchain_address_labels FINAL
    PREWHERE blockchain = 'bitcoin' AND address IN (?1)
    HAVING sign = 1
    """

    {query, [addresses]}
  end

  def addresses_labels_query(nil, addresses) do
    query = create_addresses_labels_query(nil)
    {query, [addresses]}
  end

  def addresses_labels_query(slug, addresses) do
    query = create_addresses_labels_query(slug)
    {query, [addresses, slug]}
  end

  defp create_addresses_labels_query(slug) do
    """
    SELECT address,
           label,
           concat('\{', '"owner": "', owner, '"\}') as metadata
    FROM (
        SELECT address,
               arrayJoin(labels_owners_filtered) as label_owner,
               label_owner.1 as label_raw,
               label_owner.2 as owner,
               multiIf(
                   owner = 'uniswap router', 'Uniswap Router',
                   label_raw='uniswap_ecosystem', 'Uniswap Ecosystem',
                   label_raw='cex_dex_trader', 'CEX & DEX Trader',
                   label_raw='centralized_exchange', 'CEX',
                   label_raw='decentralized_exchange', 'DEX',
                   label_raw='withdrawal', 'CEX Trader',
                   label_raw='dex_trader', 'DEX Trader',
                   #{whale_filter(slug, position: 2)}
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
                       -- if there is the `system` label for an address, we exclude other labels
                       has(label_arr, 'system'), arrayFilter(x -> x.1 = 'system', labels_owners),
                       -- if an address has a `centralized_exchange` label and at least one of the `deposit` and
                       -- `withdrawal` labels, we exclude the `deposit` and `withdrawal` labels.
                       has(label_arr, 'centralized_exchange') AND hasAny(label_arr, ['deposit', 'withdrawal']), arrayFilter(x -> x.1 NOT IN ('deposit', 'withdrawal'), labels_owners),
                       -- if there are the `dex_trader` and `decentralized_exchange` labels for an address, we exclude `dex_trader` label
                       hasAll(label_arr, ['dex_trader', 'decentralized_exchange']), arrayFilter(x -> x.1 != 'dex_trader', labels_owners),
                       -- if there are the `deposit` and `withdrawal` labels for an address, we exclude the `withdrawal` label
                       hasAll(label_arr, ['deposit', 'withdrawal']), arrayFilter(x -> x.1 != 'withdrawal', labels_owners),
                       -- if there are the `dex_trader` and `withdrawal` labels for an address, we replace these metrics to the `cex_dex_trader` label
                       hasAll(label_arr, ['dex_trader', 'withdrawal']), arrayPushFront(arrayFilter(x -> x.1 NOT IN ['dex_trader', 'withdrawal'], labels_owners), ('cex_dex_trader', arrayFilter(x -> x.1 == 'withdrawal', labels_owners)[1].2)),
                       labels_owners
                   ) as labels_owners_filtered
            FROM eth_labels_final
            ANY INNER JOIN (
                SELECT cityHash64(address) as address_hash,
                       address
                FROM (
                    SELECT lower(arrayJoin([?1])) as address
                )
            )
            USING address_hash
            PREWHERE address_hash IN (
                SELECT cityHash64(address)
                FROM (
                    SELECT lower(arrayJoin([?1])) as address
                )
            )
        )
        ANY LEFT JOIN (
          select asset_id, name from asset_metadata
        ) USING asset_id
    )
    WHERE label != 'whale_wrong'
    """
  end

  defp whale_filter(nil, _) do
    """
    label_raw='whale', concat('Whale, token:', name),
    """
  end

  defp whale_filter(slug, opts) when is_binary(slug) do
    position = Keyword.fetch!(opts, :position)

    """
    label_raw='whale' AND asset_id = (SELECT asset_id FROM asset_metadata FINAL PREWHERE name = ?#{
      position
    }), 'Whale',
    label_raw='whale' AND asset_id != (SELECT asset_id FROM asset_metadata FINAL PREWHERE name = ?#{
      position
    }), 'whale_wrong',
    """
  end

  defp get_list_of_addresses(transactions) do
    transactions
    |> Enum.flat_map(fn transaction ->
      [
        transaction.from_address && transaction.from_address.address,
        transaction.to_address && transaction.to_address.address
      ]
    end)
    |> Enum.uniq()
    |> Enum.reject(&is_nil/1)
  end

  defp do_add_labels("bitcoin", transactions, address_labels_map) do
    transactions
    |> Enum.map(fn %{to_address: to_address, from_address: from_address} = transaction ->
      from_address =
        case from_address do
          nil ->
            nil

          %{address: address} ->
            labels = Map.get(address_labels_map, address, [])
            Map.put(from_address, :labels, labels)
        end

      to_address =
        case to_address do
          nil ->
            nil

          %{address: address} ->
            labels = Map.get(address_labels_map, address, [])
            Map.put(to_address, :labels, labels)
        end

      %{transaction | to_address: to_address, from_address: from_address}
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
