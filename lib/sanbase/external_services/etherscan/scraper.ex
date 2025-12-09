defmodule Sanbase.ExternalServices.Etherscan.Scraper do
  # credo:disable-for-this-file
  use Tesla

  alias Sanbase.ExternalServices.RateLimiting
  alias Sanbase.ExternalServices.ErrorCatcher

  require Logger

  @user_agent "User-Agent: Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/74.0.3729.169 Mobile Safari/537.36"

  plug(RateLimiting.Middleware, name: :etherscan_rate_limiter)
  plug(ErrorCatcher.Middleware)
  plug(Tesla.Middleware.BaseUrl, "https://etherscan.io")
  plug(Tesla.Middleware.Headers, [{"user-agent", @user_agent}])
  plug(Tesla.Middleware.FollowRedirects, max_redirects: 10)
  plug(Tesla.Middleware.Logger)

  def fetch_address_page(address) do
    case get("/address/#{address}") do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        body

      {:ok, %Tesla.Env{status: status}} ->
        Logger.warning(
          "Invalid response from etherscan for address #{address}. Status: #{status}"
        )

        nil

      {:error, error} ->
        Logger.warning(
          "Error response from etherscan for address #{address}. Reason: #{inspect(error)}"
        )

        nil
    end
  end

  def fetch_token_page(token_name) do
    case get("/token/#{token_name}") do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        body

      {:ok, %Tesla.Env{status: status}} ->
        Logger.warning("Invalid response from etherscan for #{token_name}. Status: #{status}")

        nil

      {:error, error} ->
        Logger.warning(
          "Error response from etherscan for #{token_name}. Reason: #{inspect(error)}"
        )

        nil
    end
  end

  def parse_address_page!(nil, project_info), do: project_info

  def parse_address_page!(html, project_info) do
    {:ok, html} = Floki.parse_document(html)

    %{project_info | creation_transaction: creation_transaction(html)}
  end

  def parse_token_page!(nil, project_info), do: project_info

  def parse_token_page!(html, project_info) do
    {:ok, html} = Floki.parse_document(html)

    # We want to override the currently stored total_supply and that's the reason why the order is different than the rest of the fields
    %{
      project_info
      | total_supply: total_supply(html) || project_info.total_supply,
        # Temporarily disable the contract address scraping
        # main_contract_address: project_info.main_contract_address || main_contract_address(html),
        token_decimals: project_info.token_decimals || token_decimals(html),
        email: project_info.email || official_link(html, "Email") |> email(),
        reddit_link: project_info.reddit_link || official_link(html, "Reddit"),
        twitter_link: project_info.twitter_link || official_link(html, "Twitter"),
        btt_link: project_info.btt_link || official_link(html, "Bitcointalk"),
        blog_link: project_info.blog_link || official_link(html, "Blog"),
        github_link: project_info.github_link || official_link(html, "Github"),
        telegram_link: project_info.telegram_link || official_link(html, "Telegram"),
        slack_link: project_info.slack_link || official_link(html, "Slack"),
        facebook_link: project_info.facebook_link || official_link(html, "Facebook"),
        whitepaper_link: project_info.whitepaper_link || official_link(html, "Whitepaper")
    }
  end

  defp official_link(html, media) do
    case media do
      "Reddit" ->
        Floki.find(html, "a[href*='reddit.com']")
        |> Floki.attribute("href")
        |> List.first()

      "Twitter" ->
        Floki.find(html, "a[href*='twitter.com'], a[href*='x.com']")
        |> Floki.attribute("href")
        |> List.first()

      "Bitcointalk" ->
        Floki.find(html, "a[href*='bitcointalk.org']")
        |> Floki.attribute("href")
        |> List.first()

      "Blog" ->
        Floki.find(html, "a[href*='blog'], a[href*='medium.com'], a[href*='substack.com']")
        |> Enum.find(fn link ->
          href = Floki.attribute(link, "href") |> List.first()
          href && !String.contains?(href, "etherscan-blog")
        end)
        |> case do
          nil -> nil
          link -> Floki.attribute(link, "href") |> List.first()
        end

      "Github" ->
        Floki.find(html, "a[href*='github.com']")
        |> Floki.attribute("href")
        |> List.first()

      "Telegram" ->
        Floki.find(html, "a[href*='t.me'], a[href*='telegram.me']")
        |> Floki.attribute("href")
        |> List.first()

      "Slack" ->
        Floki.find(html, "a[href*='slack.com'], a[href*='slack.']")
        |> Floki.attribute("href")
        |> List.first()

      "Facebook" ->
        Floki.find(html, "a[href*='facebook.com']")
        |> Floki.attribute("href")
        |> List.first()

      "Whitepaper" ->
        Floki.find(html, "a[href*='whitepaper'], a[href*='.pdf']")
        |> Floki.attribute("href")
        |> List.first()

      "Email" ->
        Floki.find(html, "a[href^='mailto:']")
        |> Floki.attribute("href")
        |> List.first()

      _ ->
        nil
    end
  end

  defp email("mailto:" <> email), do: email

  defp email(_) do
    nil
  end

  defp creation_transaction(html) do
    Floki.find(html, ~s/a[title="Creator TxHash"]/)
    |> List.first()
    |> case do
      nil -> nil
      match -> Floki.text(match)
    end
  end

  defp total_supply(html) do
    # Look for the total supply in the hidden input field
    Floki.find(html, "input[id*='TotalSupply']")
    |> Floki.attribute("value")
    |> List.first()
    |> case do
      nil ->
        nil

      value ->
        value
        |> parse_total_supply()
        |> Decimal.round()
        |> Decimal.to_integer()
    end
  end

  defp main_contract_address(html) do
    Floki.find(html, "i[aria-label=\"Contract\"] + a[href*='/address/']")
    |> List.first()
    |> case do
      nil ->
        Floki.find(html, "h4:contains('Token Contract') + div a[href*='/address/']")
        |> List.first()

      match ->
        match
    end
    |> case do
      nil -> nil
      match -> Floki.text(match) |> String.trim()
    end
  end

  defp token_decimals(html) do
    html
    |> Floki.find("h4")
    |> Enum.find(fn h4 ->
      Floki.text(h4) |> String.contains?("Token Contract")
    end)
    |> case do
      nil ->
        nil

      h4 ->
        Floki.find(h4, "b")
        |> List.first()
        |> case do
          nil -> nil
          b -> Floki.text(b) |> parse_token_decimals()
        end
    end
  end

  defp parse_token_decimals(""), do: nil

  defp parse_token_decimals(token_decimals) do
    token_decimals
    |> String.trim()
    |> String.to_integer()
  end

  defp parse_total_supply(""), do: nil

  defp parse_total_supply(total_supply) when is_binary(total_supply) do
    total_supply
    |> String.trim()
    |> String.replace(",", "")
    |> Decimal.new()
  end

  defp parse_total_supply(_), do: nil
end
