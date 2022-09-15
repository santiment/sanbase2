defmodule Sanbase.ExternalServices.Coinmarketcap.CryptocurrencyInfo do
  use Tesla

  alias Sanbase.Model.Project
  alias Sanbase.ExternalServices.Coinmarketcap

  require Logger
  require Sanbase.Utils.Config, as: Config

  defstruct [:slug, :logo]

  plug(Sanbase.ExternalServices.RateLimiting.Middleware, name: :api_coinmarketcap_rate_limiter)

  plug(Tesla.Middleware.Headers, [
    {"X-CMC_PRO_API_KEY", Config.module_get(Coinmarketcap, :api_key)}
  ])

  plug(Tesla.Middleware.BaseUrl, Config.module_get(Coinmarketcap, :api_url))
  plug(Tesla.Middleware.Compression)
  plug(Tesla.Middleware.Logger)

  def fetch_data(projects) when is_list(projects) and length(projects) <= 100 do
    projects_count = Enum.count(projects)
    Logger.info("[CMC] Fetching data for #{projects_count} projects")

    coinmarketcap_ids =
      Enum.map(projects, &Project.coinmarketcap_id/1)
      |> Enum.sort()

    "v1/cryptocurrency/info?slug=#{Enum.join(coinmarketcap_ids, ",")}"
    |> get()
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Logger.info(
          "[CMC] Successfully fetched cryptocurrency info for: #{projects_count} projects."
        )

        {:ok, parse_json(body)}

      {:ok, %Tesla.Env{} = resp} ->
        handle_error_response(projects, resp)
    end
  end

  def fetch_data(_projects) do
    {:error,
     """
     Accepting over 100 projects will most probably result in very long URL.
     URLs over 2,000 characters are considered problematic.
     """}
  end

  defp handle_error_response(projects, resp) do
    %Tesla.Env{status: status, body: body} = resp
    projects_count = Enum.count(projects)

    case parse_invalid_slugs_error(body) do
      [] ->
        error_msg =
          "[CMC] Failed fetching cryptocurrency info for: #{projects_count} projects. Status: #{status}"

        Logger.warning(error_msg)
        {:error, error_msg}

      invalid_slugs when is_list(invalid_slugs) ->
        fetch_data(clean_invalid_slugs(projects, invalid_slugs))
    end
  end

  defp parse_invalid_slugs_error(error) do
    %{"status" => %{"error_message" => error_message}} = Jason.decode!(error)

    slugs =
      case error_message do
        ~s|Invalid values for "slug": | <> slugs -> slugs
        ~s|Invalid value for "slug": | <> slug -> slug
      end

    slugs
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
    |> String.split(",")
  end

  defp clean_invalid_slugs(projects, invalid_slugs) do
    Enum.reject(projects, fn project ->
      Project.coinmarketcap_id(project) in invalid_slugs
    end)
  end

  defp parse_json(json) do
    json
    |> Jason.decode!()
    |> Map.fetch!("data")
    |> Enum.map(fn {_, %{"slug" => slug, "logo" => logo}} ->
      %__MODULE__{slug: slug, logo: logo}
    end)
  end
end
