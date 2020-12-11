defmodule Sanbase.Clickhouse.ExchangeAddress do
  import Sanbase.Utils.Transform
  @supported_blockchains ["bitcoin", "ethereum", "ripple"]

  def supported_blockchains(), do: @supported_blockchains

  def exchange_names(blockchain, is_dex \\ nil)

  def exchange_names(blockchain, is_dex) when blockchain in @supported_blockchains do
    {query, args} = exchange_names_query(blockchain, is_dex)

    Sanbase.ClickhouseRepo.query_reduce(query, args, [], fn [owner], acc ->
      case is_binary(owner) and owner != "" do
        true -> [owner | acc]
        false -> acc
      end
    end)
    |> maybe_apply_function(&Enum.sort/1)
  end

  def exchange_names(blockchain, _), do: not_supported_blockchain_error(blockchain)

  def exchange_addresses(blockchain, limit \\ 1000)

  def exchange_addresses(blockchain, limit) when blockchain in @supported_blockchains do
    {query, args} = exchange_addresses_query(blockchain, limit)

    Sanbase.ClickhouseRepo.query_transform(query, args, fn [address, label, owner] ->
      %{
        address: address,
        is_dex: if(label == "decentralized_exchange", do: true, else: false),
        owner: owner
      }
    end)
  end

  def exchange_addresses(blockchain, _limit), do: not_supported_blockchain_error(blockchain)

  def exchange_addresses_for_exchange(blockchain, owner, limit \\ 1000)

  def exchange_addresses_for_exchange(blockchain, owner, limit)
      when blockchain in @supported_blockchains do
    {query, args} = exchange_addresses_for_exchange_query(blockchain, owner, limit)

    Sanbase.ClickhouseRepo.query_transform(query, args, fn [address] -> address end)
  end

  def exchange_addresses_for_exchange(blockchain, _owner, _limit),
    do: not_supported_blockchain_error(blockchain)

  # Private functions

  defp not_supported_blockchain_error(blockchain) do
    {:error,
     """
     #{blockchain} is not a supported blockchain.
     The supported blockchains are #{inspect(@supported_blockchains)}
     """}
  end

  defp exchange_names_query(blockchain, is_dex) do
    query = """
    SELECT DISTINCT lower(JSONExtractString(metadata, 'owner')) as exchange
    FROM blockchain_address_labels FINAL
    PREWHERE
      blockchain = ?1 AND
      #{maybe_is_dex(is_dex)}
    HAVING sign = 1
    ORDER BY exchange
    """

    args = [blockchain |> String.downcase()]

    {query, args}
  end

  defp exchange_addresses_query(blockchain, limit) do
    query = """
    SELECT DISTINCT(address), label, lower(JSONExtractString(metadata, 'owner'))
    FROM blockchain_address_labels FINAL
    PREWHERE blockchain = 'ethereum' AND label in ('centralized_exchange', 'decentralized_exchange')
    HAVING sign = 1
    LIMIT ?2
    """

    args = [blockchain |> String.downcase(), limit]

    {query, args}
  end

  defp exchange_addresses_for_exchange_query(blockchain, owner, limit) do
    query = """
    SELECT DISTINCT(address), label, lower(JSONExtractString(metadata, 'owner'))
    FROM blockchain_address_labels FINAL
    PREWHERE
      blockchain = ?1 AND
      lower(JSONExtractString(metadata, 'owner')) = ?2 AND
      label in ('centralized_exchange', 'decentralized_exchange')
    HAVING sign = 1
    LIMIT ?3
    """

    args = [blockchain |> String.downcase(), owner |> String.downcase(), limit]

    {query, args}
  end

  defp maybe_is_dex(nil), do: "label IN ('centralized_exchange', 'decentralized_exchange')"
  defp maybe_is_dex(true), do: "label = 'decentralized_exchange'"
  defp maybe_is_dex(false), do: "label = 'centralized_exchange'"
end
