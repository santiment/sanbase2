defmodule Sanbase.SocialData.ActiveUsers do
  import Sanbase.Utils.ErrorHandling

  require Logger
  require Sanbase.Utils.Config, as: Config

  require Mockery.Macro
  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  @recv_timeout 25_000

  def social_active_users(from, to, interval, source) do
    case active_users_request(from, to, interval, source) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        active_users_result(result)

      {:ok, %HTTPoison.Response{status_code: status}} ->
        warn_result("Error status #{status} fetching social active users")

      {:error, %HTTPoison.Error{} = error} ->
        error_result("Cannot fetch social active users #{HTTPoison.Error.message(error)}")
    end
  end

  defp active_users_request(from, to, interval, source) do
    url = "#{metrics_hub_url()}/social_active_users"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"from_timestamp", from |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
        {"to_timestamp", to |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
        {"interval", interval},
        {"source", source |> Atom.to_string()}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp active_users_result(%{"data" => map}) do
    map =
      Enum.map(map, fn {datetime, value} ->
        %{
          datetime: Sanbase.DateTimeUtils.from_iso8601!(datetime),
          value: value
        }
      end)
      |> Enum.sort_by(& &1.datetime, {:asc, DateTime})

    {:ok, map}
  end

  defp metrics_hub_url() do
    Config.module_get(Sanbase.SocialData, :metricshub_url)
  end
end
