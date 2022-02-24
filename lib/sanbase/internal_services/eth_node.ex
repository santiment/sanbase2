defmodule Sanbase.InternalServices.EthNode do
  use Tesla

  require Logger
  require Sanbase.Utils.Config, as: Config

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
        {:error,
         "Error get_transaction_by_hash for hash #{transaction_hash}. Status #{status}. Body: #{inspect(body)}"}

      {:error, error} ->
        {:error,
         "Error get_transaction_by_hash for hash #{transaction_hash}. Reason: #{inspect(error)}"}

      error ->
        {:error,
         "Error get_transaction_by_hash for hash #{transaction_hash}. Reason: #{inspect(error)}"}
    end
  end

  def get_eth_balance(addresses) when is_list(addresses) and length(addresses) > 100 do
    addresses
    |> Enum.chunk_every(100)
    |> Enum.map(&get_eth_balance/1)
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
  end

  def get_eth_balance(addresses) when is_list(addresses) do
    Logger.info("[EthNode] Get eth balance for a list of #{length(addresses)} addresses.")

    addresses = Enum.zip(Stream.iterate(1, &(&1 + 1)), addresses)

    batch =
      for {id, address} <- addresses do
        json_rpc_call("eth_getBalance", [address, "latest"], id)
      end

    {:ok, %Tesla.Env{status: 200, body: body}} =
      post(client(), "/", batch, opts: [adapter: [recv_timeout: 25_000]])

    case body do
      "" ->
        %{}

      body ->
        addresses_map = Map.new(addresses)

        body
        |> Enum.map(fn %{"id" => id, "result" => "0x" <> result} ->
          {balance, ""} = Integer.parse(result, 16)
          {Map.get(addresses_map, id), balance / @eth_decimals}
        end)
        |> Map.new()
    end
  end

  def get_eth_balance(address) do
    Logger.info("[EthNode] Get eth balance for an address.")

    with {:ok, %Tesla.Env{status: 200, body: body}} <-
           execute_json_rpc_call("eth_getBalance", [address, "latest"]),
         "0x" <> number <- body["result"],
         {balance, ""} <- Integer.parse(number, 16) do
      {:ok, balance / @eth_decimals}
    else
      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error,
         "Failed getting ETH balance for address #{address}. Status: #{status}. Body: #{inspect(body)}"}

      {:error, error} ->
        {:error, "Failed getting ETH balance for address #{address}. Reason: #{inspect(error)}"}

      error ->
        {:error, "Failed getting ETH balance for address #{address}. Reason: #{inspect(error)}"}
    end
  end

  # Private functions

  defp client() do
    parity_url = Config.get(:url)

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
