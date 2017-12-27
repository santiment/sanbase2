defmodule Sanbase.ExternalServices.Etherscan.Requests.Tx do

  alias Sanbase.ExternalServices.Etherscan.Requests
  alias __MODULE__

  defstruct [:blockNumber,
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

  defp get_query(address, startblock, endblock) do
    [
      module: "account",
      action: "txlist",
      address: address,
      startblock: startblock,
      endblock: endblock,
      sort: "desc"
    ]
  end

  def get(address, startblock, endblock) do
    Requests.get("/", query: get_query(address, startblock, endblock))
    |> case do
         %{status: 200, body: body} ->
           parse_tx_json(body)
       end
  end

  defp parse_tx_json(body) do
    response = Poison.Decode.decode(body, as: %{"result" => [%Tx{}]})
    response["result"]
    |> Enum.map( fn(tx)->
      {ts, ""} = Integer.parse(tx.timeStamp)
      %{tx | timeStamp: ts}
    end)
  end


  def get_last_outgoing_transaction(address, startblock, endblock) do
    normalized_address = String.downcase(address)
    get(address, startblock, endblock)
    |> Enum.find(fn(tx)->
      String.downcase(tx.from) == normalized_address
    end)
  end
end
