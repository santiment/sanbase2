defmodule Sanbase.ExternalServices.Coinmarketcap.Scraper do
  @moduledoc false
  use Tesla

  import Sanbase.ExternalServices.Coinmarketcap.Utils, only: [wait_rate_limit: 2]

  alias Sanbase.ExternalServices.ErrorCatcher
  alias Sanbase.ExternalServices.ProjectInfo
  alias Sanbase.ExternalServices.RateLimiting

  require Logger

  @rate_limiting_server :http_coinmarketcap_rate_limiter

  plug(RateLimiting.Middleware, name: @rate_limiting_server)
  plug(ErrorCatcher.Middleware)
  plug(Tesla.Middleware.BaseUrl, "https://coinmarketcap.com/currencies")
  plug(Tesla.Middleware.FollowRedirects, max_redirects: 10)
  plug(Tesla.Middleware.Compression)
  plug(Tesla.Middleware.Logger)

  def fetch_project_page(coinmarketcap_id) do
    case get("/#{coinmarketcap_id}/") do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Tesla.Env{status: 429} = resp} ->
        wait_rate_limit(resp, @rate_limiting_server)
        fetch_project_page(coinmarketcap_id)

      {:ok, %Tesla.Env{status: status}} ->
        error_msg = "Failed fetching project page for #{coinmarketcap_id}. Status: #{status}."

        Logger.error(error_msg)
        {:error, error_msg}

      {:error, error} ->
        error_msg = inspect(error)

        Logger.error("Error fetching project page for #{coinmarketcap_id}. Error message: #{error_msg}")

        {:error, error_msg}
    end
  end

  def parse_project_page(html, project_info) do
    {:ok, html} = Floki.parse_document(html)

    %ProjectInfo{
      project_info
      | name: project_info.name || name(html),
        ticker: project_info.ticker || ticker(html),
        main_contract_address: project_info.main_contract_address || main_contract_address(html),
        website_link: project_info.website_link || website_link(html),
        github_link: project_info.github_link || github_link(html),
        etherscan_token_name: project_info.etherscan_token_name || etherscan_token_name(html)
    }
  end

  # Private functions

  defp name(html) do
    html
    |> Floki.attribute(".logo-32x32", "alt")
    |> List.first()
  end

  defp ticker(html) do
    case Floki.find(html, "h1 > .text-bold.h3.text-gray.text-large") do
      [{_, _, [str]}] when is_binary(str) ->
        String.replace(str, ~r/[\(\)]/, "")

      _ ->
        nil
    end
  end

  defp website_link(html) do
    html
    |> Floki.attribute(".bottom-margin-2x a:fl-contains('Website')", "href")
    |> List.first()
  end

  defp github_link(html) do
    github_link =
      html
      |> Floki.attribute("a:fl-contains('Source Code')", "href")
      |> List.first()

    if github_link && String.contains?(github_link, "https://github.com/") do
      github_link
    end
  end

  defp etherscan_token_name(html) do
    html
    |> Floki.attribute("a:fl-contains('Explorer')", "href")
    |> Enum.map(fn link ->
      Regex.run(~r{https://etherscan.io/token/(.+)}, link)
    end)
    |> Enum.find(& &1)
    |> case do
      nil -> nil
      list -> List.last(list)
    end
  end

  defp main_contract_address(html) do
    html
    |> Floki.attribute("a:fl-contains('Explorer')", "href")
    |> Enum.map(fn link ->
      Regex.run(~r{https://ethplorer.io/address/(.+)}, link)
    end)
    |> Enum.find(& &1)
    |> case do
      nil -> nil
      list -> List.last(list)
    end
  end
end
