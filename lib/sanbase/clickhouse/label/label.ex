defmodule Sanbase.Clickhouse.Label do
  @moduledoc """
  Labeling addresses
  """

  import Sanbase.Utils.Transform, only: [maybe_apply_function: 2]

  import Sanbase.Metric.SqlQuery.Helper,
    only: [label_id_by_label_fqn_filter: 2, label_id_by_label_key_filter: 2]

  alias Sanbase.Accounts.User

  @type label :: %{
          name: String.t(),
          metadata: String.t()
        }

  @create_label_topic "label_changes"

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

    Sanbase.ClickhouseRepo.query_transform(query, [blockchain], fn [label] ->
      label
    end)
  end

  def addresses_by_labels(label_fqn_or_fqns, opts \\ [])

  def addresses_by_labels(label_fqn_or_fqns, opts) do
    blockchain = Keyword.get(opts, :blockchain)

    label_fqns = label_fqn_or_fqns |> List.wrap() |> Enum.map(&String.downcase/1)

    {query, args} = addresses_by_label_fqns_query(label_fqns, blockchain)

    Sanbase.ClickhouseRepo.query_reduce(
      query,
      args,
      %{},
      fn [address, blockchain, label_fqn], acc ->
        Map.update(acc, {address, blockchain}, [label_fqn], &[label_fqn | &1])
      end
    )
    |> maybe_apply_function(fn address_blockchain_labels_map ->
      apply_addresses_labels_combinator(address_blockchain_labels_map, label_fqns, opts)
    end)
  end

  def addresses_by_label_keys(label_key_or_keys, opts \\ [])

  def addresses_by_label_keys(label_key_or_keys, opts) do
    blockchain = Keyword.get(opts, :blockchain)

    label_keys = label_key_or_keys |> List.wrap() |> Enum.map(&String.downcase/1)

    {query, args} = addresses_by_label_keys_query(label_keys, blockchain)

    Sanbase.ClickhouseRepo.query_reduce(
      query,
      args,
      %{},
      fn [address, blockchain, label_fqn], acc ->
        Map.update(acc, {address, blockchain}, [label_fqn], &[label_fqn | &1])
      end
    )
    |> maybe_apply_function(fn address_blockchain_labels_map ->
      apply_addresses_labels_combinator(address_blockchain_labels_map, label_keys, [])
    end)
  end

  defp apply_addresses_labels_combinator(
         address_blockchain_labels_map,
         label_fqns,
         opts
       ) do
    case Keyword.get(opts, :labels_combinator, :or) do
      :or ->
        address_blockchain_labels_map

      :and ->
        # Reject all addresses that don't have all the required label_fqns
        Enum.reject(address_blockchain_labels_map, fn {_address_blockchain, address_label_fqns} ->
          Enum.any?(label_fqns, &(&1 not in address_label_fqns))
        end)
    end
    |> Enum.map(fn {{address, blockchain}, _labels} ->
      %{
        address: address,
        infrastructure: Sanbase.BlockchainAddress.infrastructure_from_blockchain(blockchain)
      }
    end)
  end

  def add_labels(_, []), do: {:ok, []}

  def add_labels(slug, maps) when is_list(maps) do
    addresses = get_list_of_addresses(maps)
    blockchain = slug_to_blockchain(slug)
    {query, args} = addresses_labels_query(slug, blockchain, addresses)

    result =
      Sanbase.ClickhouseRepo.query_reduce(
        query,
        args,
        %{},
        fn [address, label, metadata], acc ->
          label = %{name: label, metadata: metadata, origin: "santiment"}
          Map.update(acc, address, [label], &[label | &1])
        end
      )

    case result do
      {:ok, labels_map} -> {:ok, do_add_labels(maps, labels_map)}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_address_labels(_slug, []), do: {:ok, %{}}

  def get_address_labels(slug, addresses) when is_list(addresses) do
    blockchain = slug_to_blockchain(slug)
    {query, args} = addresses_labels_query(slug, blockchain, addresses)

    Sanbase.ClickhouseRepo.query_reduce(
      query,
      args,
      %{},
      fn [address, label, metadata], acc ->
        label = %{name: label, metadata: metadata, origin: "santiment"}
        Map.update(acc, address, [label], &[label | &1])
      end
    )
  end

  def add_user_labels_to_address(%User{id: user_id, username: username}, selector, labels)
      when not is_nil(username) do
    for label <- labels do
      data = %{
        type: "SINGLE",
        event: "CREATE",
        blockchain:
          Sanbase.BlockchainAddress.blockchain_from_infrastructure(selector.infrastructure),
        address: Sanbase.BlockchainAddress.to_internal_format(selector.address),
        label: %{
          key: label,
          owner: username,
          owner_id: user_id
        },
        event_dt: DateTime.to_iso8601(DateTime.utc_now()),
        change_reason: %{}
      }

      key = label <> data.event_dt
      {key, Jason.encode!(data)}
    end
    |> Sanbase.KafkaExporter.send_data_to_topic_from_current_process(@create_label_topic)
  end

  def add_user_labels_to_address(%User{username: nil}, _selector, _labels),
    do: {:error, "Username is required for creating custom address labels"}

  # Private functions

  # For backwards compatibility, if the slug is nil treat it as ethereum blockchain
  def slug_to_blockchain(nil), do: "ethereum"

  def slug_to_blockchain(slug),
    do: Sanbase.Model.Project.slug_to_blockchain(slug)

  def addresses_by_label_fqns_query(label_fqns, _blockchain = nil) do
    query = """
    SELECT address, blockchain, dictGetString('default.labels_dict', 'fqn', label_id) AS label_fqn
    FROM label_addresses
    PREWHERE
      #{label_id_by_label_fqn_filter(label_fqns, argument_position: 1)}
    GROUP BY address, blockchain, label_id
    LIMIT 20000
    """

    args = [label_fqns]
    {query, args}
  end

  def addresses_by_label_fqns_query(label_fqns, blockchain) do
    query = """
    SELECT address, blockchain, dictGetString('default.labels_dict', 'fqn', label_id) AS label_fqn
    FROM label_addresses
    PREWHERE
      #{label_id_by_label_fqn_filter(label_fqns, argument_position: 1)} AND
      blockchain = ?2
    GROUP BY address, blockchain, label_id
    LIMIT 20000
    """

    args = [label_fqns, blockchain]
    {query, args}
  end

  def addresses_by_label_keys_query(label_keys, _blockchain = nil) do
    query = """
    SELECT address, blockchain, dictGetString('default.labels_dict', 'fqn', label_id) AS label_fqn
    FROM label_addresses
    PREWHERE
      #{label_id_by_label_key_filter(label_keys, argument_position: 1)}
    GROUP BY address, blockchain, label_id
    LIMIT 20000
    """

    args = [label_keys]
    {query, args}
  end

  def addresses_by_label_keys_query(label_keys, blockchain) do
    query = """
    SELECT address, blockchain, dictGetString('default.labels_dict', 'fqn', label_id) AS label_fqn
    FROM label_addresses
    PREWHERE
      #{label_id_by_label_key_filter(label_keys, argument_position: 1)} AND
      blockchain = ?2
    GROUP BY address, blockchain, label_id
    LIMIT 20000
    """

    args = [label_keys, blockchain]
    {query, args}
  end

  defp addresses_labels_query(slug, "ethereum", addresses) do
    query = create_addresses_labels_query(slug)

    args =
      case slug do
        nil -> [addresses]
        _ -> [addresses, slug]
      end

    {query, args}
  end

  defp addresses_labels_query(_slug, blockchain, addresses) do
    query = """
    SELECT address, label, metadata
    FROM(
      SELECT address, label, argMax(metadata, version) AS metadata, argMax(sign, version) AS sign
      FROM blockchain_address_labels
      PREWHERE blockchain = ?1 AND address IN (?2)
      GROUP BY blockchain, asset_id, label, address
      HAVING sign = 1
    )
    """

    {query, [blockchain, addresses]}
  end

  defp get_list_of_addresses(maps) do
    maps
    |> Enum.flat_map(fn map ->
      [
        Map.get(map, :address) && map.address.address,
        Map.get(map, :from_address) && map.from_address.address,
        Map.get(map, :to_address) && map.to_address.address
      ]
    end)
    |> Enum.uniq()
    |> Enum.reject(&is_nil/1)
  end

  defp do_add_labels(maps, labels_map) do
    add_labels = fn
      # In this case the address type does not exist, so the result is not used
      nil ->
        nil

      map ->
        labels = Map.get(labels_map, map.address, []) |> Enum.sort_by(& &1.name)
        Map.put(map, :labels, labels)
    end

    maps
    |> Enum.map(fn %{} = map ->
      map
      |> Map.replace(:address, add_labels.(Map.get(map, :address)))
      |> Map.replace(:from_address, add_labels.(Map.get(map, :from_address)))
      |> Map.replace(:to_address, add_labels.(Map.get(map, :to_address)))
    end)
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
    label_raw='whale' AND asset_id = (SELECT asset_id FROM asset_metadata FINAL PREWHERE name = ?#{position}), 'Whale',
    label_raw='whale' AND asset_id != (SELECT asset_id FROM asset_metadata FINAL PREWHERE name = ?#{position}), 'whale_wrong',
    """
  end

  defp create_owner_name(user) do
    if user.username do
      if String.starts_with?(user.username, "0x") do
        "0x" <> String.slice(user.username, -4, 4)
      else
        user.username
      end
    else
      generate_username(user.id)
    end
  end

  def generate_username(user_id) do
    :crypto.hash(:sha256, to_string(user_id))
    |> Base.encode16()
    |> binary_part(0, 6)
  end
end
