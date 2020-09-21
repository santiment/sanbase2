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
    SELECT lower(address) as address, label, metadata
    FROM blockchain_address_labels FINAL
    PREWHERE
      blockchain = 'ethereum' AND
      ((label = 'whale' and asset_id = (SELECT argMax(asset_id, computed_at) FROM asset_metadata FINAL PREWHERE name = ?1))
        OR (label != 'whale' and asset_id = 0)) AND
      lower(address) IN (?2)
    HAVING sign = 1
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
