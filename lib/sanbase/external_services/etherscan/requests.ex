defmodule Sanbase.ExternalServices.Etherscan.Requests do

  #require Logger
  use Tesla


  alias Sanbase.ExternalServices.Etherscan.RateLimiter
  alias Sanbase.ExternalServices.Etherscan.Requests

  plug RateLimiter.Tesla
  plug Tesla.Middleware.BaseUrl, "https://api.etherscan.io/api"
  plug Tesla.Middleware.Compression

  plug Tesla.Middleware.Query, [
    apikey: Keyword.get(config(), :apikey)
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

  def config do
    Application.get_env(:sanbase, __MODULE__)
  end
end
