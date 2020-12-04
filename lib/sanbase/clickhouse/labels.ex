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
    SELECT address_hash,
           asset_id,
           address,
           splitByChar(',', labels) as label_arr,
           splitByChar(',', owners) as owner_arr,
           arrayZip(label_arr, owner_arr) as labels_owners,
           multiIf(
               has(label_arr, 'uniswap_ecosystem'), ('Uniswap Ecosystem', arrayFilter(x -> x.1 = 'uniswap_ecosystem', labels_owners)[1].2),
               has(label_arr, 'decentralized_exchange'), ('DEX', arrayFilter(x -> x.1 = 'decentralized_exchange', labels_owners)[1].2),
               has(label_arr, 'defi'), ('DeFi', arrayFilter(x -> x.1 = 'defi', labels_owners)[1].2),
               has(label_arr, 'deployer'), ('Deployer', arrayFilter(x -> x.1 = 'deployer', labels_owners)[1].2),
               has(label_arr, 'stablecoin'), ('Stablecoin', arrayFilter(x -> x.1 = 'stablecoin', labels_owners)[1].2),
               hasAll(label_arr, ['withdrawal', 'dex_trader']), ('CEX & DEX Trader', arrayFilter(x -> x.1 = 'withdrawal', labels_owners)[1].2),
               hasAll(label_arr, ['withdrawal', 'deposit']), ('CEX Deposit', arrayFilter(x -> x.1 = 'deposit', labels_owners)[1].2),
               has(label_arr, 'deposit'), ('CEX Deposit', arrayFilter(x -> x.1 = 'deposit', labels_owners)[1].2),
               has(label_arr, 'withdrawal'), ('CEX Trader', arrayFilter(x -> x.1 = 'withdrawal', labels_owners)[1].2),
               has(label_arr, 'dex_trader'), ('DEX Trader', arrayFilter(x -> x.1 = 'dex_trader', labels_owners)[1].2),
               has(label_arr, 'whale') AND asset_id = (SELECT asset_id FROM asset_metadata FINAL PREWHERE name = ?1), ('Whale', arrayFilter(x -> x.1 = 'whale', labels_owners)[1].2),
               has(label_arr, 'whale') AND asset_id != (SELECT asset_id FROM asset_metadata FINAL PREWHERE name = ?1), ('wrong_whale', ''),
               has(label_arr, 'centralized_exchange'), ('CEX', arrayFilter(x -> x.1 = 'centralized_exchange', labels_owners)[1].2),
               has(label_arr, 'makerdao-cdp-owner'), ('MakerDAO CDP Owner', arrayFilter(x -> x.1 = 'makerdao-cdp-owner', labels_owners)[1].2),
               has(label_arr, 'makerdao-bite-keeper'), ('MakerDAO Bite Keeper', arrayFilter(x -> x.1 = 'makerdao-bite-keeper', labels_owners)[1].2),
               has(label_arr, 'genesis'), ('Genesis', arrayFilter(x -> x.1 = 'genesis', labels_owners)[1].2),
               has(label_arr, 'proxy'), ('Proxy', arrayFilter(x -> x.1 = 'proxy', labels_owners)[1].2),
               has(label_arr, 'system'), ('System', arrayFilter(x -> x.1 = 'system', labels_owners)[1].2),
               has(label_arr, 'miner'), ('Miner', arrayFilter(x -> x.1 = 'miner', labels_owners)[1].2),
               (label_arr[1], owner_arr[1])
            ) as label_owner,
           label_owner.1 as label,
           label_owner.2 as owner
    FROM eth_labels_final
    ANY INNER JOIN (
        SELECT cityHash64(address) as address_hash,
               address
        FROM (
            SELECT arrayJoin([?2]) as address
        )
    )
    USING address_hash
    PREWHERE address_hash IN (
        SELECT cityHash64(address)
        FROM (
            SELECT lower(arrayJoin([?2])) as address
        )
    )
        AND NOT has(label_arr, 'system')
    )
    WHERE label != 'wrong_whale'
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
