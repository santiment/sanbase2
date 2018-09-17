defmodule Sanbase.InternalServices.Parity do
  require Sanbase.Utils.Config, as: Config

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

  def get_eth_balance(address) do
    with %Tesla.Env{status: 200, body: body} <-
           post(client(), "/", json_rpc_call("eth_getBalance", [address])),
         "0x" <> number <- body["result"],
         {balance, ""} <- Integer.parse(number, 16) do
      {:ok, balance}
    else
      error -> {:error, error}
    end
  end

  # Private functions

  defp client() do
    parity_url = Config.get(:url)

    Tesla.build_client([
      Sanbase.ExternalServices.ErrorCatcher.Middleware,
      {Tesla.Middleware.BaseUrl, parity_url},
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
