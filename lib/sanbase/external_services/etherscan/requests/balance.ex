defmodule Sanbase.ExternalServices.Etherscan.Requests.Balance do

  alias Sanbase.ExternalServices.Etherscan.Requests
  alias __MODULE__

  defstruct [:status, :message, :result]

  defp get_query(address) do
    [
      module: "account",
      action: "balance",
      address: address,
      tag: "latest",
    ]
  end

  def get(address) do
    Requests.get("/", query: get_query(address))
    |> case do
         %{status: 200, body: body} -> Poison.Decode.decode(body, as: %Balance{})
       end
  end

end
