defmodule Sanbase.Clickhouse.Labels do
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
    addresses = get_list_of_addresses(transactions)
    {query, args} = addresses_labels_query(addresses)

    Sanbase.ClickhouseRepo.query_reduce(query, args, %{}, fn [address, label, metadata], acc ->
      address = String.downcase(address)

      Map.update(acc, address, [], fn labels ->
        metadata =
          case Jason.decode(metadata) do
            {:ok, _} -> metadata
            {:error, _} -> ~s|""|
          end

        label = %{name: label, metadata: metadata}
        Enum.uniq_by(labels ++ [label], fn %{name: name} -> name end)
      end)
    end)
    |> case do
      {:ok, address_labels_map} ->
        {:ok, do_add_labels(transactions, address_labels_map)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # helpers
  defp addresses_labels_query(addresses) do
    query = """
    SELECT address, label, metadata
    FROM blockchain_address_labels FINAL
    PREWHERE address IN (?1) and sign = 1
    """

    {query, [addresses]}
  end

  defp get_list_of_addresses(transactions) do
    transactions
    |> Enum.map(fn transaction ->
      [
        transaction.from_address.address,
        transaction.to_address.address
      ]
    end)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.downcase/1)
  end

  defp do_add_labels(transactions, address_labels_map) do
    transactions
    |> Enum.map(fn %{from_address: from, to_address: to} = transaction ->
      from = Map.put(from, :labels, Map.get(address_labels_map, from.address, []))
      to = Map.put(to, :labels, Map.get(address_labels_map, to.address, []))

      %{transaction | from_address: from, to_address: to}
    end)
  end
end
