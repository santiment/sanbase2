defmodule Sanbase.ExternalServices.Etherscan.Requests.InternalTx do
  alias Sanbase.ExternalServices.Etherscan.Requests
  alias __MODULE__

  defstruct [
    :blockNumber,
    :timeStamp,
    :hash,
    :from,
    :to,
    :value,
    :contractAddress,
    :input,
    :type,
    :gas,
    :gasUsed,
    :traceId,
    :isError,
    :errCode
  ]

  defp get_query(address) do
    [
      module: "account",
      action: "txlistinternal",
      address: address,
      startblock: 0,
      endblock: 99_999_999,
      sort: "desc"
    ]
  end

  def get(address) do
    Requests.get("/", query: get_query(address))
    |> case do
      %{status: 200, body: body} ->
        response = Poison.Decode.decode(body, as: %{result: [%InternalTx{}]})
        response.result
    end
  end
end
