defmodule Sanbase.ExternalServices.Coinmarketcap.ProjectInfo do
  defstruct [
    :coinmarketcap_id,
    :name,
    :website_link,
    :github_link,
    :smart_contract_address,
    :ticker,
  ]

  use Tesla

  plug RateLimiting.Middleware, name: :html_coinmarketcap_rate_limiter
  plug Tesla.Middleware.BaseUrl, "https://graphs.coinmarketcap.com/currencies"
  plug Tesla.Middleware.Compression
  plug Tesla.Middleware.Logger

  def fetch_project_page(coinmarketcap_id) do
    %Tesla.Env{status: 200, body: body} = get("/#{coinmarketcap_id}")

    body
  end

  def scrape_info(coinmarketcap_id, html) do
    %__MODULE__{
      coinmarketcap_id: coinmarketcap_id,
      name: name(html),
      ticker: ticker(html),
      smart_contract_address: smart_contract_address(html),
      website_link: website_link(html),
      github_link: github_link(html)
    }
  end

  defp name(html) do
    Floki.attribute(html, ".currency-logo-32x32", "alt")
    |> hd
  end

  defp ticker(html) do
    Floki.find(html, "h1 small.bold")
    |> hd
    |> Floki.text
    |> String.replace(~r/[\(\)]/, "")
  end

  defp website_link(html) do
    Floki.attribute(html, ".bottom-margin-2x a:fl-contains('Website')", "href")
    |> hd
  end

  defp github_link(html) do
    Floki.attribute(html, "a:fl-contains('Source Code')", "href")
    |> hd
  end

  defp smart_contract_address(html) do
    Floki.attribute(html, "a:fl-contains('Explorer')", "href")
    |> Enum.map(fn link ->
      Regex.run(~r{https://ethplorer.io/address/(.+)}, link)
    end)
    |> Enum.find(&(&1))
    |> List.last
  end

  defp creator_transaction(html) do
    Floki.find(html, "[data-original-title='Creator Transaction Hash']")
    |> hd
    |> Floki.text
  end
end
