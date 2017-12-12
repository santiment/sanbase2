defmodule Sanbase.Parity do
  import Sanbase.Utils, only: [parse_config_value: 1]

  use Tesla

  def get_transaction_by_hash(transaction_hash) do
    with %Tesla.Env{status: 200, body: body} <- post(client(), "/", json_rpc_call("eth_getTransactionByHash", [transaction_hash])),
      %{"result" => result} <- body do
        {:ok, result}
      else
        error -> {:error, error}
    end
  end

  def get_latest_block_number!() do
    case get_latest_block_number() do
      {:ok, blockNumber} -> blockNumber
      {:error, error} -> raise error
    end
  end

  def get_latest_block_number do
    with %Tesla.Env{status: 200, body: body} <- post(client(), "/", json_rpc_call("eth_blockNumber", [])),
      "0x" <> number <- body["result"],
      {blockNumber, ""} <- Integer.parse(number, 16) do
        {:ok, blockNumber}
      else
        error -> {:error, error}
    end
  end

  defp client() do
    parity_url = config(:url)
    basic_auth_username = config(:basic_auth_username)
    basic_auth_password = config(:basic_auth_password)

    Tesla.build_client [
      {Tesla.Middleware.BaseUrl, parity_url},
      {Tesla.Middleware.BasicAuth, username: basic_auth_username, password: basic_auth_password},
      Tesla.Middleware.JSON,
      Tesla.Middleware.Logger
    ]
  end

  defp json_rpc_call(method, params) do
    %{
      method: method,
      params: params,
      id: 1,
      jsonrpc: "2.0"
    }
  end

  defp config(key) do
    Application.get_env(:sanbase, __MODULE__)
    |> Keyword.get(key)
    |> parse_config_value()
  end
end
