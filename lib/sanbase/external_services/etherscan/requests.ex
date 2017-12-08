defmodule Sanbase.ExternalServices.Etherscan.Requests do

  use Tesla

  alias Sanbase.ExternalServices.RateLimiting
  alias Sanbase.ExternalServices.Etherscan.Requests

  import Sanbase.Utils, only: [parse_config_value: 1]

  plug RateLimiting.Middleware, name: :etherscan_rate_limiter
  plug Tesla.Middleware.BaseUrl, "https://api.etherscan.io/api"
  plug Tesla.Middleware.Compression

  plug Tesla.Middleware.Query, [
    apikey: api_key()
  ]
  plug Tesla.Middleware.Logger

  def get_latest_block_number do
    get("/",
      query: [
       module: "proxy",
       action: "eth_BlockNumber"
      ])
    |> case do
        %{status: 200, body: body} -> parse_latest_block_number(body)
       end
  end

  def parse_latest_block_number(body) do
    result = Poison.decode!(body)
    {res, ""} = result["result"]
    |> String.slice(2..-1)
    |> Integer.parse(16)
    res
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
