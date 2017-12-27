defmodule Sanbase.ExternalServices.Etherscan.Requests do

  use Tesla

  alias Sanbase.ExternalServices.RateLimiting

  import Sanbase.Utils, only: [parse_config_value: 1]

  plug RateLimiting.Middleware, name: :etherscan_rate_limiter
  plug Tesla.Middleware.BaseUrl, "https://api.etherscan.io/api"
  plug Tesla.Middleware.Compression
  plug Tesla.Middleware.JSON

  plug Tesla.Middleware.Query, [
    apikey: api_key()
  ]
  plug Tesla.Middleware.Logger

  def get_abi(address) do
    with %Tesla.Env{status: 200, body: body} <- get("/", query: [module: "contract", action: "getabi", address: address]),
      %{"result" => abi} <- body do
      {:ok, abi}
    else
      error -> {:error, error}
    end
  end

  defp api_key() do
    config()
    |> Keyword.get(:apikey)
    |> parse_config_value()
  end

  defp config do
    Application.get_env(:sanbase, __MODULE__)
  end
end
