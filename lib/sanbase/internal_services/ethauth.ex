defmodule Sanbase.InternalServices.Ethauth do
  use Tesla

  alias Sanbase.Utils.Config

  require Logger

  @san_token_decimals 1_000_000_000_000_000_000
  @tesla_opts [adapter: [recv_timeout: 15_000]]

  def token_decimals(contract) when is_binary(contract) do
    Logger.info("[Ethauth] Get token decimals for #{contract}")

    case get(client(), "decimals", query: [contract: contract], opts: @tesla_opts) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Jason.decode(body)

      {:ok, %Tesla.Env{status: status}} ->
        {:error, "Error fetching token decimals for #{contract}. Status: #{status}"}

      {:error, error} ->
        {:error, "Error fetching token decimals for #{contract}. Reason: #{inspect(error)}"}
    end
  end

  def total_supply(contract) when is_binary(contract) do
    Logger.info("[Ethauth] Get total supply for #{contract}")

    with {:ok, %Tesla.Env{status: 200, body: body}} <-
           get(client(), "total_supply", query: [contract: contract], opts: @tesla_opts),
         {:ok, total_supply} <- Jason.decode(body),
         {:ok, decimals} when is_integer(decimals) <- token_decimals(contract) do
      {:ok, div(total_supply, Sanbase.Math.ipow(10, decimals))}
    else
      {:ok, %Tesla.Env{status: status}} ->
        {:error, "Error fetching total supply for #{contract}. Status: #{status}"}

      {:error, error} ->
        {:error, "Error fetching total supply for #{contract}. Reason: #{inspect(error)}"}
    end
  end

  @doc ~s"""
  Verify that a user that claims to own a given Ethereum address acttually owns it.
  """
  @spec is_valid_signature?(any(), any()) :: boolean() | {:error, String.t()}
  def is_valid_signature?(address, signature) do
    Logger.info(["[Ethauth] Verify signature"])

    message = "Login in Santiment with address #{address}"

    with {:ok, %Tesla.Env{status: 200, body: body}} <-
           get(client(), "verify",
             query: [signer: address, signature: signature, message: message],
             opts: @tesla_opts
           ),
         {:ok, %{"is_valid" => is_valid}} <- Jason.decode(body) do
      is_valid
    else
      {:ok, %Tesla.Env{status: status}} ->
        {:error, "Error veryfing signature for address. #{address}. Status: #{status}"}

      {:error, error} ->
        {:error, "Error veryfing signature for address. #{address}. Reason: #{inspect(error)}"}
    end
  end

  @doc ~s"""
  Fetch the latest SAN balance of `address`
  """
  def san_balance(address) do
    Logger.info("[Ethauth] Get san balance for #{address}")

    get(client(), "san_balance", query: [addr: address], opts: @tesla_opts)
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        san_balance = body |> Sanbase.Math.to_float()

        {:ok, san_balance / @san_token_decimals}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error,
         "Error fetching SAN balance for address. #{address}. Status: #{status}. Body: #{inspect(body)}"}

      {:error, error} ->
        {:error, "Error fetching SAN balance for address. #{address}. Reason: #{inspect(error)}"}
    end
  end

  defp client() do
    ethauth_url = Config.module_get(__MODULE__, :url)

    Tesla.client([
      Sanbase.ExternalServices.ErrorCatcher.Middleware,
      {Tesla.Middleware.BaseUrl, ethauth_url},
      Tesla.Middleware.Logger
    ])
  end
end
