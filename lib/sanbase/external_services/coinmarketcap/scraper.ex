defmodule Sanbase.ExternalServices.Coinmarketcap.Scraper do
  use Tesla

  alias Sanbase.ExternalServices.RateLimiting

  plug RateLimiting.Middleware, name: :http_coinmarketcap_rate_limiter
  plug Tesla.Middleware.BaseUrl, "https://coinmarketcap.com/currencies"
  plug Tesla.Middleware.Compression
  plug Tesla.Middleware.Logger

  def fetch_project_page(coinmarketcap_id) do
    %Tesla.Env{status: 200, body: body} = get("/#{coinmarketcap_id}/")

    body
  end

  def parse_project_page(html, project_info) do
    project_info
    |> struct!(
      name: name(html),
      ticker: ticker(html),
      main_contract_address: main_contract_address(html),
      website_link: website_link(html),
      github_link: github_link(html)
    )
  end

  defp name(html) do
    Floki.attribute(html, ".currency-logo-32x32", "alt")
    |> List.first
  end

  defp ticker(html) do
    Floki.find(html, "h1 small.bold")
    |> hd
    |> Floki.text
    |> String.replace(~r/[\(\)]/, "")
  end

  defp website_link(html) do
    Floki.attribute(html, ".bottom-margin-2x a:fl-contains('Website')", "href")
    |> List.first
  end

  defp github_link(html) do
    Floki.attribute(html, "a:fl-contains('Source Code')", "href")
    |> List.first
  end

  defp main_contract_address(html) do
    Floki.attribute(html, "a:fl-contains('Explorer')", "href")
    |> Enum.map(fn link ->
      Regex.run(~r{https://ethplorer.io/address/(.+)}, link)
    end)
    |> Enum.find(&(&1))
    |> case do
      nil -> nil
      list -> List.last(list)
    end
  end
end
