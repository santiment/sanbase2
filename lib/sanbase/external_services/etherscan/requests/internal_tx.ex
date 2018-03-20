defmodule Sanbase.ExternalServices.Etherscan.Requests.InternalTx do
  alias Sanbase.ExternalServices.Etherscan.Requests
  alias __MODULE__

  require Logger

  defstruct [
    :hash,
    :blockNumber,
    :timeStamp,
    :from,
    :to,
    :value,
    :isError,
    :errCode
  ]

  def get(address, startblock, endblock) do
    Requests.get("/", query: get_query(address, startblock, endblock))
    |> case do
      %{status: 200, body: body} ->
        {:ok, parse_tx_json(body)}

      %{status: status, body: body} ->
        error = "Error fetching transactions for #{address}. Status code: #{status}: #{body}"
        Logger.warn(error)
        {:error, error}
      error ->
        {:error, error}
    end
  end

  # Private functions

  defp get_query(address, startblock, endblock) do
    [
      module: "account",
      action: "txlistinternal",
      address: address,
      startblock: startblock,
      endblock: endblock,
      sort: "asc",
      page: 1,
      offset: 5000
    ]
  end

  defp parse_tx_json(body) do
    response = Poison.Decode.decode(body, as: %{"result" => [%InternalTx{}]})

    response["result"]
    |> Enum.map(fn tx ->
      {ts, ""} = Integer.parse(tx.timeStamp)
      %{tx | timeStamp: ts}
    end)
  end
end
