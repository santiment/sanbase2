defmodule Sanbase.Geoip do
  require Logger

  def fetch_geo_data(ip) do
    tag = "Geoip.fetch_geo_data"
    url = "https://api.ipgeolocation.io/ipgeo?ip=#{ip}&include=security"
    headers = [{"Origin", "https://ipgeolocation.io"}]

    case HTTPoison.get(url, headers, timeout: 1000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body
        |> Jason.decode()
        |> case do
          {:ok, data} ->
            {:ok, data}

          {:error, _} = error ->
            Logger.error(
              "[#{tag}] Error parsing response from IP Geolocation API. Full response: #{inspect(error)}"
            )

            error
        end

      {:ok, %HTTPoison.Response{status_code: status_code} = response} ->
        Logger.error(
          "[#{tag}] Received status code #{status_code} from IP Geolocation API. Full response: #{inspect(response)}"
        )

        {:error, :unexpected_status_code}

      {:error, %HTTPoison.Error{reason: reason} = error} ->
        Logger.error("[#{tag}] HTTPoison Error: #{reason}. Full error: #{inspect(error)}")
        {:error, :http_error}

      other ->
        Logger.error(
          "[#{tag}] Unknown error when calling IP Geolocation API. Full error: #{inspect(other)}"
        )

        {:error, :unknown_error}
    end
  end
end
