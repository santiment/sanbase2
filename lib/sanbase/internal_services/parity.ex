defmodule Sanbase.InternalServices.Parity do
  require Sanbase.Utils.Config
  alias Sanbase.Utils.Config

  use Tesla

  def get_transaction_by_hash!(transaction_hash) do
    case get_transaction_by_hash(transaction_hash) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  def get_transaction_by_hash(transaction_hash) do
    with %Tesla.Env{status: 200, body: body} <-
           post(client(), "/", json_rpc_call("eth_getTransactionByHash", [transaction_hash])),
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
    with %Tesla.Env{status: 200, body: body} <-
           post(client(), "/", json_rpc_call("eth_blockNumber", [])),
         "0x" <> number <- body["result"],
         {blockNumber, ""} <- Integer.parse(number, 16) do
      {:ok, blockNumber}
    else
      error -> {:error, error}
    end
  end

  defp client() do
    parity_url = Config.get(:url)
    basic_auth_username = Config.get(:basic_auth_username)
    basic_auth_password = Config.get(:basic_auth_password)

    Tesla.build_client([
      {Tesla.Middleware.BaseUrl, parity_url},
      {Tesla.Middleware.BasicAuth, username: basic_auth_username, password: basic_auth_password},
      Tesla.Middleware.JSON,
      Tesla.Middleware.Logger
    ])
  end

  defp json_rpc_call(method, params) do
    %{
      method: method,
      params: params,
      id: 1,
      jsonrpc: "2.0"
    }
  end
end
