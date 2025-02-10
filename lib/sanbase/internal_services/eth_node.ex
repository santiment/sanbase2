defmodule Sanbase.InternalServices.EthNode do
  @moduledoc false
  use Tesla

  alias Sanbase.Utils.Config

  require Logger

  @eth_decimals 1_000_000_000_000_000_000

  def get_transaction_by_hash!(transaction_hash) do
    case get_transaction_by_hash(transaction_hash) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  def get_transaction_by_hash(transaction_hash) do
    Logger.info("[EthNode] Get transaction by hash.")

    with {:ok, %Tesla.Env{status: 200, body: body}} <-
           execute_json_rpc_call("eth_getTransactionByHash", [transaction_hash]),
         %{"result" => result} <- body do
      {:ok, result}
    else
      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, "Error get_transaction_by_hash for hash #{transaction_hash}. Status #{status}. Body: #{inspect(body)}"}

      {:error, error} ->
        {:error, "Error get_transaction_by_hash for hash #{transaction_hash}. Reason: #{inspect(error)}"}

      error ->
        {:error, "Error get_transaction_by_hash for hash #{transaction_hash}. Reason: #{inspect(error)}"}
    end
  end

  def get_eth_balance(addresses) when is_list(addresses) and length(addresses) > 100 do
    addresses
    |> Enum.chunk_every(100)
    |> Enum.map(&get_eth_balance/1)
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
  end

  def get_eth_balance(addresses) when is_list(addresses) do
    Logger.info("[EthNode] Get ETH balance for a list of #{length(addresses)} addresses.")

    addresses = Enum.with_index(addresses, 1)

    case get_eth_balance_batch_call(addresses) do
      {:ok, %Tesla.Env{status: 200, body: ""}} ->
        %{}

      {:ok, %Tesla.Env{status: 200, body: body}} ->
        id_to_address_map = Map.new(addresses, fn {addr, index} -> {index, addr} end)

        Map.new(body, fn %{"id" => id, "result" => hex_balance} ->
          {Map.get(id_to_address_map, id), hex_to_eth_balance(hex_balance)}
        end)

      _ ->
        {:error, "Failed getting ETH balance for a list of addresses"}
    end
  end

  def get_eth_balance(address) do
    Logger.info("[EthNode] Get eth balance for an address.")

    case execute_json_rpc_call("eth_getBalance", [address, "latest"]) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        hex_balance = body["result"]
        {:ok, hex_to_eth_balance(hex_balance)}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, "Failed getting ETH balance for address #{address}. Status: #{status}. Body: #{inspect(body)}"}

      {:error, error} ->
        {:error, "Failed getting ETH balance for address #{address}. Reason: #{inspect(error)}"}

      error ->
        {:error, "Failed getting ETH balance for address #{address}. Reason: #{inspect(error)}"}
    end
  end

  # Private functions

  defp hex_to_eth_balance("0x" <> hex_balance) do
    {balance, ""} = Integer.parse(hex_balance, 16)
    balance / @eth_decimals
  end

  defp get_eth_balance_batch_call(addresses) do
    batch =
      for {address, index} <- addresses do
        json_rpc_call("eth_getBalance", [address, "latest"], index)
      end

    post(client(), "/", batch, opts: [adapter: [recv_timeout: 25_000]])
  end

  defp client do
    parity_url = Config.module_get(__MODULE__, :url)

    Tesla.client([
      Sanbase.ExternalServices.ErrorCatcher.Middleware,
      {Tesla.Middleware.BaseUrl, parity_url},
      Tesla.Middleware.JSON,
      Tesla.Middleware.Logger
    ])
  end

  def execute_json_rpc_call(method, params) do
    post(
      client(),
      "/",
      json_rpc_call(method, params),
      opts: [adapter: [recv_timeout: 15_000]]
    )
  end

  defp json_rpc_call(method, params, id \\ 1) do
    %{
      method: method,
      params: params,
      id: id,
      jsonrpc: "2.0"
    }
  end
end
