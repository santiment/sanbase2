defmodule Sanbase.TechIndicators.MetricAnomaly do
  import Sanbase.Utils.ErrorHandling

  require Logger
  require Sanbase.Utils.Config, as: Config

  require Mockery.Macro
  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  @recv_timeout 15_000

  @type anomaly_point :: %{
          datetime: DateTime.t(),
          value: number()
        }

  @spec metric_anomaly(
          atom(),
          String.t(),
          DateTime.t(),
          DateTime.t(),
          String.t()
        ) :: {:error, String.t()} | {:ok, [anomaly_point()]}
  def metric_anomaly(
        metric,
        slug,
        from,
        to,
        interval
      ) do
    url = "#{tech_indicators_url()}/indicator/anomalies_detection"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"metric", metric |> Atom.to_string()},
        {"project_slug", slug},
        {"from_timestamp", DateTime.to_unix(from)},
        {"to_timestamp", DateTime.to_unix(to)},
        {"interval", interval}
      ]
    ]

    http_client().get(url, [], options)
    |> handle_result(slug, metric)
    |> case do
      {:ok, result} ->
        {:ok, result}

      {:error, error} ->
        {:error, error}
    end
  end

  defp handle_result({:ok, %HTTPoison.Response{status_code: 200, body: body}}, _, _) do
    body
    |> Jason.decode!()
    |> anomalies_result()
  end

  defp handle_result({:ok, %HTTPoison.Response{status_code: status, body: body}}, slug, metric) do
    warn_result(
      "Error status #{status} fetching anomalies for project with slug: #{slug} for metric #{
        metric
      } - #{body}"
    )
  end

  defp handle_result({:error, %HTTPoison.Error{} = error}, slug, metric) do
    error_result(
      "Cannot fetch anomalies for project with slug: #{slug} for metric #{metric} - #{
        HTTPoison.Error.message(error)
      }"
    )
  end

  defp anomalies_result(result) do
    result =
      result
      |> Enum.map(fn %{
                       "datetime" => datetime,
                       "value" => value
                     } ->
        %{
          datetime: DateTime.from_unix!(datetime),
          value: value
        }
      end)

    {:ok, result}
  end

  defp tech_indicators_url(), do: Config.module_get(Sanbase.TechIndicators, :url)
end
