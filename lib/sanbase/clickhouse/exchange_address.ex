defmodule Sanbase.Clickhouse.ExchangeAddress do
  @supported_blockchains ["bitcoin", "ethereum", "ripple"]

  def supported_blockchains(), do: @supported_blockchains

  def exchange_names(blockchain) when blockchain in @supported_blockchains do
    {query, args} = exchange_names_query(blockchain)

    Sanbase.ClickhouseRepo.query_transform(query, args, fn [owner] -> owner end)
  end

  def exchange_names(blockchain), do: not_supported_blockchain_error(blockchain)

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

  defp exchange_names_query(blockchain) do
    query = """
    SELECT DISTINCT JSONExtractString(metadata, 'owner')
    FROM blockchain_address_labels
    PREWHERE blockchain = ?1
    """

    args = [blockchain |> String.downcase()]

    {query, args}
  end

  defp exchange_addresses_query(blockchain, limit) do
    query = """
    SELECT DISTINCT(address), label, JSONExtractString(metadata, 'owner')
    FROM blockchain_address_labels
    PREWHERE blockchain = 'ethereum' AND label in ('centralized_exchange', 'decentralized_exchange')
    LIMIT 1000
    """

    args = [blockchain |> String.downcase(), limit]

    {query, args}
  end

  defp exchange_addresses_for_exchange_query(blockchain, owner, limit) do
    query = """
    SELECT DISTINCT(address), label, JSONExtractString(metadata, 'owner')
    FROM blockchain_address_labels
    PREWHERE
      blockchain = ?1 AND
      lower(JSONExtractString(metadata, 'owner')) = ?2 AND
      label in ('centralized_exchange', 'decentralized_exchange')
    LIMIT ?3
    """

    args = [blockchain |> String.downcase(), owner |> String.downcase(), limit]

    {query, args}
  end
end
