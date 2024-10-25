defmodule Sanbase.SocialData.ActiveUsers do
  import Sanbase.Utils.ErrorHandling

  require Logger
  alias Sanbase.Utils.Config

  require Mockery.Macro
  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  @recv_timeout 25_000

  def social_active_users(%{source: source}, from, to, interval)
      when source in ["telegram", "twitter_crypto", "twitter", "reddit", "bitcointalk"] do
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

  def social_active_users(%{source: source}, _from, _to, _interval)
      when source not in ["telegram", "twitter_crypto"] do
    error_result("Invalid source argument. Source should be one of telegram or twitter_crypto")
  end

  def social_active_users(_, _, _, _) do
    error_result("Invalid arguments.")
  end

  defp active_users_request(from, to, interval, source) do
    url = "#{metrics_hub_url()}/social_active_users"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"from_timestamp", from |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
        {"to_timestamp", to |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
        {"interval", interval},
        {"source", source}
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
