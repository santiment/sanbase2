defmodule Sanbase.InternalServices.Parity do
  use Tesla

  require Sanbase.Utils.Config, as: Config

  @eth_decimals 1_000_000_000_000_000_000

  def get_transaction_by_hash!(transaction_hash) do
    case get_transaction_by_hash(transaction_hash) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  def get_transaction_by_hash(transaction_hash) do
    with {:ok, %Tesla.Env{status: 200, body: body}} <-
           post(
             client(),
             "/",
             json_rpc_call("eth_getTransactionByHash", [transaction_hash]),
             opts: [adapter: [recv_timeout: 15_000]]
           ),
         %{"result" => result} <- body do
      {:ok, result}
    else
      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error,
         "Error get_transaction_by_hash for hash #{transaction_hash}. Status #{status}. Body: #{
           inspect(body)
         }"}

      {:error, error} ->
        {:error,
         "Error get_transaction_by_hash for hash #{transaction_hash}. Reason: #{inspect(error)}"}

      error ->
        {:error,
         "Error get_transaction_by_hash for hash #{transaction_hash}. Reason: #{inspect(error)}"}
    end
  end

  def get_eth_balance(address) do
    with {:ok, %Tesla.Env{status: 200, body: body}} <-
           post(client(), "/", json_rpc_call("eth_getBalance", [address]),
             opts: [adapter: [recv_timeout: 15_000]]
           ),
         "0x" <> number <- body["result"],
         {balance, ""} <- Integer.parse(number, 16) do
      {:ok, balance / @eth_decimals}
    else
      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error,
         "Failed getting ETH balance for address #{address}. Status: #{status}. Body: #{
           inspect(body)
         }"}

      {:error, error} ->
        {:error, "Failed getting ETH balance for address #{address}. Reason: #{inspect(error)}"}

      error ->
        {:error, "Failed getting ETH balance for address #{address}. Reason: #{inspect(error)}"}
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
