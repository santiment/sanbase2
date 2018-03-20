defmodule Sanbase.ExternalServices.Etherscan.Requests do
  @moduledoc ~s"""
    Module which is used to send requests to etherscan.io
  """
  use Tesla

  require Sanbase.Utils.Config

  alias Sanbase.Utils.Config
  alias Sanbase.ExternalServices.RateLimiting
  alias Sanbase.ExternalServices.ErrorCatcher

  plug(RateLimiting.Middleware, name: :etherscan_rate_limiter)
  plug(ErrorCatcher.Middleware)
  plug(Tesla.Middleware.BaseUrl, "https://api.etherscan.io/api")
  plug(Tesla.Middleware.Compression)
  plug(Tesla.Middleware.JSON)

  plug(Tesla.Middleware.Query, apikey: Config.get(:api_key))
  plug(Tesla.Middleware.Logger)

  def get_abi(address) do
    with %Tesla.Env{status: 200, body: body} <-
           get("/", query: [module: "contract", action: "getabi", address: address]),
         %{"result" => abi} <- body do
      {:ok, abi}
    else
      error -> {:error, error}
    end
  end
end
