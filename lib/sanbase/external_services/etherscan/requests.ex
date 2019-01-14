defmodule Sanbase.ExternalServices.Etherscan.Requests do
  @moduledoc ~s"""
    Module which is used to send requests to etherscan.io.

    Used to fetch a contract's ABI. The ABI is not stored on the blockchain and
    cannot be fetched from Parity
  """
  use Tesla

  require Sanbase.Utils.Config, as: Config

  alias Sanbase.ExternalServices.{RateLimiting, ErrorCatcher}

  plug(RateLimiting.Middleware, name: :etherscan_rate_limiter)
  plug(ErrorCatcher.Middleware)
  plug(Tesla.Middleware.BaseUrl, "https://api.etherscan.io/api")
  plug(Tesla.Middleware.FollowRedirects, max_redirects: 10)
  plug(Tesla.Middleware.Compression)
  plug(Tesla.Middleware.JSON)

  plug(Tesla.Middleware.Query, apikey: Config.get(:api_key))
  plug(Tesla.Middleware.Logger)

  def get_abi(address) do
    get("/", query: [module: "contract", action: "getabi", address: address])
    |> case do
      {:ok, %Tesla.Env{status: 200, body: %{"result" => abi}}} ->
        {:ok, abi}

      {:ok, %Tesla.Env{status: status}} ->
        {:error, "Get ABI for address #{address} failed. Status: #{status}."}

      {:error, error} ->
        {:error, "Get ABI for address #{address} failed. Reason: #{inspect(error)}"}
    end
  end
end
