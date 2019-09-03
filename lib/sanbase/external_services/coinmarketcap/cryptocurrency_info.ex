defmodule Sanbase.ExternalServices.Coinmarketcap.CryptocurrencyInfo do
  defstruct [:slug, :logo]

  use Tesla

  require Logger
  require Sanbase.Utils.Config, as: Config

  alias Sanbase.Model.Project
  alias Sanbase.ExternalServices.Coinmarketcap

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

    coinmarketcap_ids = Enum.map(projects, &Project.coinmarketcap_id/1)

    "v1/cryptocurrency/info?slug=#{Enum.join(coinmarketcap_ids, ",")}"
    |> get()
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Logger.info(
          "[CMC] Successfully fetched cryptocurrency info for: #{projects_count} projects."
        )

        {:ok, parse_json(body)}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        case parse_invalid_slugs_error(body) do
          [] ->
            error_msg =
              "[CMC] Failed fetching cryptocurrency info for: #{projects_count} projects. Status: #{
                status
              }"

            Logger.warn(error_msg)
            {:error, error_msg}

          invalid_slugs when is_list(invalid_slugs) ->
            cleaned =
              Enum.reject(projects, fn project ->
                Project.coinmarketcap_id(project) in invalid_slugs
              end)

            fetch_data(cleaned)
        end

      {:error, error} ->
        error_msg =
          "[CMC] Error fetching cryptocurrency info for: #{projects_count} projects. Error message: #{
            inspect(error)
          }"

        Logger.warn(error_msg)
        {:error, error_msg}
    end
  end

  def fetch_data(_projects) do
    {:error,
     """
     Accepting over 100 projects will most probably result in very long URL.
     URLs over 2,000 characters are considered problematic.
     """}
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

  defp parse_json(json) do
    json
    |> Jason.decode!()
    |> Map.get("data")
    |> Enum.map(fn {_, %{"slug" => slug, "logo" => logo}} ->
      %__MODULE__{slug: slug, logo: logo}
    end)
  end
end
