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
    :from,
    :to,
    :value,
    :isError,
    :txreceipt_status
  ]

  @doc ~s"""
    Issues a HTTP GET request to etherscan.io api to get the transactions from
    `startblock` to `endblock` in ascending order.
    Returns `{:ok, list()}` on success, `{:error, String.t}` otherwise
  """
  @spec get(String.t(), Integer.t(), Integer.t()) :: {:ok, list()} | {:error, String.t()}
  def get(address, startblock, endblock) do
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

  # The offset is the max number of transactions that will be returned. As we are
  # making the next query with a recalculated starblock so we are effectivly
  # exploiting the offset to be used only for limiting the number of fetched transactions
  # and not for pagination
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
