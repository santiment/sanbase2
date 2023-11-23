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
    query_struct = all_labels_query()

    Sanbase.ClickhouseRepo.query_transform(query_struct, fn [label] -> label end)
  end

  def list_all(blockchain) do
    query_struct = all_blockchain_labels_query(blockchain)

    Sanbase.ClickhouseRepo.query_transform(query_struct, fn [label] ->
      label
    end)
  end

  def addresses_by_labels(label_fqn_or_fqns, opts \\ [])

  def addresses_by_labels(label_fqn_or_fqns, opts) do
    blockchain = Keyword.get(opts, :blockchain)

    label_fqns = label_fqn_or_fqns |> List.wrap() |> Enum.map(&String.downcase/1)

    query_struct = addresses_by_label_fqns_query(label_fqns, blockchain)

    Sanbase.ClickhouseRepo.query_reduce(
      query_struct,
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

    query_struct = addresses_by_label_keys_query(label_keys, blockchain)

    Sanbase.ClickhouseRepo.query_reduce(
      query_struct,
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
    query_struct = addresses_labels_query(slug, blockchain, addresses)

    result =
      Sanbase.ClickhouseRepo.query_reduce(
        query_struct,
        %{},
        fn [address, label, metadata], acc ->
          new_label = %{name: label, metadata: metadata, origin: "santiment"}
          updated_labels = update_labels(acc[address], new_label)
          Map.put(acc, address, updated_labels)
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
    query_struct = addresses_labels_query(slug, blockchain, addresses)

    Sanbase.ClickhouseRepo.query_reduce(
      query_struct,
      %{},
      fn [address, label, metadata], acc ->
        new_label = %{name: label, metadata: metadata, origin: "santiment"}
        updated_labels = update_labels(acc[address], new_label)
        Map.put(acc, address, updated_labels)
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

  defp all_labels_query() do
    sql = """
    SELECT DISTINCT(label) FROM blockchain_address_labels
    """

    params = %{}
    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp all_blockchain_labels_query(blockchain) do
    sql = """
    SELECT DISTINCT(label)
    FROM blockchain_address_labels
    PREWHERE blockchain = {{blockchain}}
    """

    params = %{blockchain: blockchain}
    Sanbase.Clickhouse.Query.new(sql, params)
  end

  # For backwards compatibility, if the slug is nil treat it as ethereum blockchain
  defp slug_to_blockchain(nil), do: "ethereum"

  defp slug_to_blockchain(slug),
    do: Sanbase.Project.slug_to_blockchain(slug)

  def addresses_by_label_fqns_query(label_fqns, nil = _blockchain) do
    sql = """
    SELECT address, blockchain, dictGetString('default.labels_dict', 'fqn', label_id) AS label_fqn
    FROM label_addresses
    PREWHERE
      #{label_id_by_label_fqn_filter(label_fqns, argument_name: "label_fqns")}
    GROUP BY address, blockchain, label_id
    LIMIT 20000
    """

    params = %{label_fqns: label_fqns}
    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def addresses_by_label_fqns_query(label_fqns, blockchain) do
    sql = """
    SELECT address, blockchain, dictGetString('default.labels_dict', 'fqn', label_id) AS label_fqn
    FROM label_addresses
    PREWHERE
      #{label_id_by_label_fqn_filter(label_fqns, argument_name: "label_fqns")} AND
      blockchain = {{blockchain}}
    GROUP BY address, blockchain, label_id
    LIMIT 20000
    """

    params = %{label_fqns: label_fqns, blockchain: blockchain}
    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def addresses_by_label_keys_query(label_keys, nil = _blockchain) do
    sql = """
    SELECT address, blockchain, dictGetString('default.labels_dict', 'fqn', label_id) AS label_fqn
    FROM label_addresses
    PREWHERE
      #{label_id_by_label_key_filter(label_keys, argument_name: "label_keys")}
    GROUP BY address, blockchain, label_id
    LIMIT 20000
    """

    params = %{label_keys: label_keys}
    Sanbase.Clickhouse.Query.new(sql, params)
  end

  def addresses_by_label_keys_query(label_keys, blockchain) do
    sql = """
    SELECT address, blockchain, dictGetString('default.labels_dict', 'fqn', label_id) AS label_fqn
    FROM label_addresses
    PREWHERE
      #{label_id_by_label_key_filter(label_keys, argument_name: "label_keys")} AND
      blockchain = {{blockchain}}
    GROUP BY address, blockchain, label_id
    LIMIT 20000
    """

    params = %{label_keys: label_keys, blockchain: blockchain}
    Sanbase.Clickhouse.Query.new(sql, params)
  end

  # update_labels/2 is used to avoid duplicates
  defp update_labels(existing_labels, new_label) do
    case existing_labels do
      nil ->
        [new_label]

      _ ->
        if Enum.any?(existing_labels, fn label -> label.name == new_label.name end) do
          existing_labels
        else
          [new_label | existing_labels]
        end
    end
  end

  defp addresses_labels_query(slug, "ethereum", addresses) do
    sql = create_addresses_labels_query(slug)
    params = %{addresses: addresses, slug: slug}

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp addresses_labels_query(_slug, blockchain, addresses) do
    sql = """
    SELECT address, label, metadata
    FROM(
      SELECT address, label, argMax(metadata, version) AS metadata, argMax(sign, version) AS sign
      FROM blockchain_address_labels
      PREWHERE blockchain = {{blockchain}} AND address IN ({{addresses}})
      GROUP BY blockchain, asset_id, label, address
      HAVING sign = 1
    )
    """

    params = %{blockchain: blockchain, addresses: addresses}
    Sanbase.Clickhouse.Query.new(sql, params)
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
    -- Query using v2
    SELECT
        address,
        -- Creating Proper View of key
        arrayStringConcat(
            arrayMap(x -> concat(upper(substring(x, 1, 1)), substring(x, 2, length(x) - 1)),
            splitByChar('_',
                -- If key == 'owner' -> we will take value
                multiIf(
                        key_v = 'owner', value,
                        key_v
                    )
            )), ' '
        ) as key,

        multiIf(
            key_v = 'owner',  concat('{\"owner\": \"', value, '\"}'),
            key_v != 'owner', value,
            ''
        ) as metadata
    FROM
        (
        SELECT
            address,
            arrayJoin(key_value_cleaned) as key_value,
            key_value.1 as key_v,
            key_value.2 as value
        FROM (
            SELECT
                -- Here we can add filtration rules
                a.address as address,
                groupArray(m.key) AS keys_arr,
                groupArray(m.value) AS values_arr,
                arrayZip(keys_arr, values_arr) as labels_owners,
                multiIf(
                -- Exclude owner: cefi
                has(keys_arr, 'cefi'), arrayFilter(x -> x.1 != 'cefi', labels_owners),

                -- If nft_marketplace - exclude nft_trader, nft_user, nft_user_threshold
                has(keys_arr, 'nft_marketplace'), arrayFilter(x -> x.1 NOT IN ('nft_trader', 'nft_user', 'nft_user_threshold'), labels_owners),

                -- If decentralized_exchange(defi) exclude dex_user
                has(keys_arr, 'decentralized_exchange'), arrayFilter(x -> x.1 != 'dex_user', labels_owners),

                -- If centralized_exchange + depost + withdrawal - Delete "depost + withdrawal"
                has(keys_arr, 'centralized_exchange') AND hasAny(keys_arr, ['deposit', 'withdrawal']), arrayFilter(x -> x.1 NOT IN ('deposit', 'withdrawal'), labels_owners),

                -- If depost + withdrawal - exclude withdrawal
                hasAll(keys_arr, ['deposit', 'withdrawal']), arrayFilter(x -> x.1 != 'withdrawal', labels_owners),
                labels_owners

                -- Check whale label by asset_name
                ) as key_value_cleaned
            FROM
                (
                    SELECT
                        address,
                        label_id
                    FROM
                        current_label_addresses
                    WHERE
                        address IN [{{addresses}}]
                ) AS a
            LEFT JOIN
                (
                    SELECT
                        label_id,
                        key,
                        value,
                        asset_name,
                        multiIf(
                            asset_name != {{slug}} AND key = 'whale', NULL,
                            key
                        ) AS filtered_key
                    FROM
                        label_metadata
                ) AS m USING (label_id)
            WHERE m.filtered_key IS NOT NULL
            GROUP BY address
        )
    )
    """
  end

  def generate_username(user_id) do
    :crypto.hash(:sha256, to_string(user_id))
    |> Base.encode16()
    |> binary_part(0, 6)
  end
end
