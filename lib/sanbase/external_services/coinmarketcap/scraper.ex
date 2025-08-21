defmodule Sanbase.ExternalServices.Coinmarketcap.Scraper do
  use Tesla

  import Sanbase.ExternalServices.Coinmarketcap.Utils, only: [wait_rate_limit: 2]
  require Logger

  alias Sanbase.ExternalServices.{RateLimiting, ErrorCatcher}

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

        Logger.error(
          "Error fetching project page for #{coinmarketcap_id}. Error message: #{error_msg}"
        )

        {:error, error_msg}
    end
  end

  def parse_project_page(html, project_info) do
    {:ok, html} = Floki.parse_document(html)

    %{
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
    Floki.attribute(html, "[data-role='coin-name']", "title")
    |> List.first()
  end

  defp ticker(html) do
    Floki.attribute(html, "[data-role='coin-symbol']", "text")
    |> List.first()
    |> case do
      nil ->
        Floki.find(html, "[data-role='coin-symbol']")
        |> Floki.text()
        |> String.trim()

      ticker ->
        ticker
    end
  end

  defp website_link(html) do
    website_link =
      Floki.attribute(html, "a[data-test='chip-website-link']", "href")
      |> List.first()

    # Handle protocol-relative URLs (starting with //)
    case website_link do
      nil -> nil
      "//" <> _ = url -> "https:#{url}"
      url when is_binary(url) -> url
      _ -> nil
    end
  end

  defp github_link(html) do
    # First try to find GitHub link in the socials section
    github_link =
      Floki.attribute(
        html,
        "[data-test='section-coin-stats-socials'] a[href*='github.com']",
        "href"
      )
      |> List.first()

    case github_link do
      "//" <> _ = url -> "https:#{url}"
      url when is_binary(url) -> url
      _ -> nil
    end
  end

  defp etherscan_token_name(html) do
    Floki.attribute(
      html,
      "[data-test='section-coin-stats-explorers'] a[href*='etherscan.io'",
      "href"
    )
    |> Enum.map(fn link ->
      Regex.run(~r{etherscan.io/token/(.+)}, link)
    end)
    |> Enum.find(& &1)
    |> case do
      nil -> nil
      list -> List.last(list)
    end
  end

  defp main_contract_address(html) do
    # Look for contract address in __NEXT_DATA__ script tag first
    _contract_address =
      Floki.find(html, "script#__NEXT_DATA__")
      |> List.first()
      |> case do
        nil ->
          nil

        script ->
          script_content =
            script
            |> Floki.raw_html()

          case Regex.run(~r/"contractAddress":"(0x[a-fA-F0-9]{40})"/, script_content) do
            [_, address] -> address
            _ -> nil
          end
      end

    # # If not found in __NEXT_DATA__, search in head section
    # contract_address ||
    #   Floki.find(html, "head")
    #   |> Floki.text()
    #   |> String.trim()
    #   |> then(fn text ->
    #     case Regex.run(~r/"contractAddress":"(0x[a-fA-F0-9]{40})"/, text) do
    #       [_, address] -> address
    #       _ -> nil
    #     end
    #   end)
    #
    # # If not found in head, search in body section
    # contract_address ||
    #   Floki.find(html, "body")
    #   |> Floki.text()
    #   |> String.trim()
    #   |> then(fn text ->
    #     case Regex.run(~r/"contractAddress":"(0x[a-fA-F0-9]{40})"/, text) do
    #       [_, address] -> address
    #       _ -> nil
    #     end
    #   end)
    #
    # # Fallback: look for any 0x address in the entire document
    # contract_address ||
    #   Floki.find(html, "html")
    #   |> Floki.text()
    #   |> String.trim()
    #   |> then(fn text ->
    #     case Regex.run(~r/0x[a-fA-F0-9]{40}/, text) do
    #       [address] -> address
    #       _ -> nil
    #     end
    #   end)
  end
end
