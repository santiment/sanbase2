defmodule Sanbase.ExternalServices.Coinmarketcap.Ticker do
  # A module which fetches the ticker data from coinmarketcap
  defstruct [:id, :name, :symbol, :price_usd, :rank, :'24h_volume_usd', :market_cap_usd, :last_updated]

  alias Sanbase.ExternalServices.RateLimiting

  use Tesla

  plug RateLimiting.Middleware, name: :api_coinmarketcap_rate_limiter
  plug Tesla.Middleware.BaseUrl, "https://api.coinmarketcap.com/v1/ticker"
  plug Tesla.Middleware.Compression
  plug Tesla.Middleware.Logger

  alias Sanbase.ExternalServices.Coinmarketcap.Ticker

  def fetch_data() do
    "/?limit=1000"
    |> get()
    |> case do
	 %{status: 200, body: body} ->
	   parse_json(body)
       end
  end

  def parse_json(json) do
    json
    |> Poison.decode!(as: [%Ticker{}])
    |> Enum.map(&make_timestamp_integer/1)
  end

  defp make_timestamp_integer(ticker) do
    {ts, ""} = Integer.parse(ticker.last_updated)
    %{ticker| last_updated: ts}
  end
end
