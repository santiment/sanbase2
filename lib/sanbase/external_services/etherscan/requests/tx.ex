defmodule Sanbase.ExternalServices.Etherscan.Requests.Tx do
  @moduledoc ~s"""
    Module for fetching transactions from etherscan.io for a given address.
  """
  alias Sanbase.ExternalServices.Etherscan.Requests
  alias __MODULE__

  require Logger

  defstruct [
    :blockNumber,
    :timeStamp,
    :hash,
    :nonce,
    :blockHash,
    :transactionIndex,
    :from,
    :to,
    :value,
    :gas,
    :gasPrice,
    :isError,
    :txreceipt_status,
    :input,
    :contractAddress,
    :cumulativeGasUsed,
    :gasUsed,
    :confirmations
  ]

  @doc ~s"""
    Issues a HTTP GET request to etherscan.io api to get the transactions from
    `startblock` to `endblock` in ascending order.
    Returns `{:ok, list()}` on success, `{:error, String.t}` otherwise
  """
  @spec get_all_transactions(String.t(), Integer.t(), Integer.t()) ::
          {:ok, list()} | {:error, String.t()}
  def get_all_transactions(address, startblock, endblock) do
    String.downcase(address) |> get(startblock, endblock)
  end

  # Private functions

  defp get(address, startblock, endblock) do
    Requests.get("/", query: get_query(address, startblock, endblock))
    |> case do
      %{status: 200, body: body} ->
        {:ok, parse_tx_json(body)}

      %{status: status, body: body} ->
        error = "Error fetching transactions for #{address}. Status code: #{status}: #{body}"
        Logger.warn(error)
        {:error, error}
    end
  end

  defp get_query(address, startblock, endblock) do
    [
      module: "account",
      action: "txlist",
      address: address,
      startblock: startblock,
      endblock: endblock,
      sort: "asc",
      page: 1,
      offset: 2500
    ]
  end

  defp parse_tx_json(body) do
    response = Poison.Decode.decode(body, as: %{"result" => [%Tx{}]})

    response["result"]
    |> Enum.map(fn tx ->
      {ts, ""} = Integer.parse(tx.timeStamp)
      %{tx | timeStamp: ts}
    end)
  end
end
