defmodule Sanbase.ExternalServices.Etherscan.Requests.Balance do
  alias Sanbase.ExternalServices.Etherscan.Requests
  alias __MODULE__

  require Logger

  defstruct [:status, :message, :result]

  def get_balance(address) do
    Requests.get("/", query: get_query(address))
    |> case do
      %{status: 200, body: body} ->
        Poison.Decode.decode(body, as: %Balance{})

      %{status: status, body: body} ->
        error = "Error fetching transactions for #{address}. Status code: #{status}: #{body}"
        Logger.warn(error)
        nil

      _ ->
        error = "Error fetching transactions for #{address}"
        Logger.warn(error)
        nil
    end
  end

  # Helper functions

  defp get_query(address) do
    [
      module: "account",
      action: "balance",
      address: address,
      tag: "latest"
    ]
  end
end
