defmodule Sanbase.ExternalServices.Etherscan.Scraper do
  use Tesla

  alias Decimal, as: D
  alias Sanbase.ExternalServices.RateLimiting
  alias Sanbase.ExternalServices.ProjectInfo

  plug RateLimiting.Middleware, name: :etherscan_rate_limiter
  plug Tesla.Middleware.BaseUrl, "https://etherscan.io"
  plug Tesla.Middleware.Logger

  @max_redirects 10

  def fetch_address_page(address) do
    %Tesla.Env{status: 200, body: body} = get("/address/#{address}")

    body
  end

  def fetch_token_page(token_name, redirects \\ 0)

  def fetch_token_page(_, @max_redirects), do: raise "Too many redirects"

  def fetch_token_page(token_name, redirects) do
    case get("/token/#{token_name}") do
      %Tesla.Env{status: 200, body: body} -> body
      %Tesla.Env{status: 302, headers: %{"location" => "/token/" <> name}} ->
        fetch_token_page(name, redirects + 1)
    end
  end

  def parse_address_page(html, project_info) do
    %ProjectInfo{project_info |
      creation_transaction: creation_transaction(html)
    }
  end

  def parse_token_page(html, project_info) do
    %ProjectInfo{project_info |
      total_supply: D.mult(total_supply(html), D.new(:math.pow(10, token_decimals(html)))) |> D.to_integer,
      main_contract_address: main_contract_address(html) || project_info.main_contract_address,
      token_decimals: token_decimals(html)
    }
  end

  defp creation_transaction(html) do
    Floki.find(html, ~s/a[title="Creator Transaction Hash"]/)
    |> hd
    |> Floki.text
  end

  defp total_supply(html) do
    Floki.find(html, ~s/td:fl-contains('Total Supply') + td/)
    |> hd
    |> Floki.text
    |> parse_total_supply
  end

  defp main_contract_address(html) do
    Floki.find(html, ~s/td:fl-contains('Contract Address') + td/)
    |> hd
    |> Floki.text
  end

  defp token_decimals(html) do
    Floki.find(html, ~s/td:fl-contains('Token Decimals') + td/)
    |> hd
    |> Floki.text
    |> parse_token_decimals
  end

  defp parse_token_decimals(nil), do: 0

  defp parse_token_decimals(token_decimals) do
    token_decimals
    |> String.trim()
    |> String.to_integer()
  end

  defp parse_total_supply(nil), do: D.new(0)

  defp parse_total_supply(total_supply) do
    total_supply
    |> String.trim()
    |> String.replace(",", "")
    |> String.split()
    |> List.first
    |> D.new
  end
end
