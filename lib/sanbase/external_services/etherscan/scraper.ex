defmodule Sanbase.ExternalServices.Etherscan.Scraper do
  use Tesla

  plug RateLimiting.Middleware, name: :etherscan_rate_limiter
  plug Tesla.Middleware.BaseUrl, "https://etherscan.io"
  plug Tesla.Middleware.Logger

  def fetch_address_page(address) do
    %Tesla.Env{status: 200, body: body} = get("/address/#{address}")

    body
  end

  def parse_address_page(html) do
    %{
      creator_transaction: creator_transaction(html)
    }
  end

  defp creator_transaction(html) do
    Floki.find(html, ~s/a[title="Creator Transaction Hash"]/)
    |> hd
    |> Floki.text
  end
end
