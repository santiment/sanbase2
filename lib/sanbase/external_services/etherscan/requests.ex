defmodule Sanbase.ExternalServices.Etherscan.Requests do

  use Tesla

  alias Sanbase.ExternalServices.RateLimiting
  alias Sanbase.ExternalServices.Etherscan.Requests

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
    |> parse_api_key()
  end

  defp parse_api_key({:system, env_key}), do: System.get_env(env_key)

  defp parse_api_key(value), do: value

  defp config do
    Application.get_env(:sanbase, __MODULE__)
  end
end
