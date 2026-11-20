defmodule Sanbase.SocialData.Community do
  use Mockery.Macro

  import Sanbase.Utils.ErrorHandling

  alias Sanbase.Utils.Config

  require Logger

  defp http_client(), do: mockable(HTTPoison)

  @recv_timeout 25_000
  @sources [:telegram, :reddit]

  def community_messages_count(selector, from, to, interval, source)
      when source in [:all, "all", :total, "total"] do
    @sources
    |> Sanbase.Parallel.map(
      fn source -> community_messages_count(selector, from, to, interval, source) end,
      max_concurrency: 4,
      # Outlast the HTTP recv_timeout so the request returns its own error
      timeout: @recv_timeout + 5_000,
      on_timeout: :kill_task,
      zip_input_on_exit: true
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, data}, {:ok, acc} ->
        {:cont, {:ok, data ++ acc}}

      {:error, _} = error, _acc ->
        {:halt, error}

      {:exit, {source, reason}}, _acc ->
        error =
          warn_result(
            "Dropped community messages count for source #{source} and #{inspect(selector)}. Reason: #{inspect(reason)}"
          )

        {:halt, error}
    end)
    |> Sanbase.Utils.Transform.maybe_apply_function(
      &Sanbase.Utils.Transform.sum_by_datetime(&1, :mentions_count)
    )
  end

  def community_messages_count(%{slug: slug}, from, to, interval, source) do
    community_messages_count_request(slug, from, to, interval, source |> to_string())
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, result} ->
            community_messages_count_result(result)

          {:error, error} ->
            error_result(
              "Cannot decode community messages count response for project #{slug}: #{Exception.message(error)}"
            )
        end

      {:ok, %HTTPoison.Response{status_code: status}} ->
        warn_result(
          "Error status #{status} fetching community messages count for project #{slug}"
        )

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch community messages count data for project #{slug}: #{HTTPoison.Error.message(error)}"
        )
    end
  end

  def community_messages_count(argument) do
    {:error, "Invalid argument for community_messages_count #{inspect(argument)}"}
  end

  defp community_messages_count_request(slug, from, to, interval, source) do
    url = "#{metrics_hub_url()}/social_volume_unit"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"slugs", slug},
        {"from_timestamp", from |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
        {"to_timestamp", to |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
        {"interval", interval},
        {"source", to_string(source)},
        {"search_text", "*"},
        {"include_units", "own"}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp community_messages_count_result(%{"data" => data}) do
    result =
      data
      |> Enum.map(fn {timestamp, value} ->
        %{
          datetime: Sanbase.Utils.DateTime.from_iso8601!(timestamp),
          mentions_count: value
        }
      end)
      |> Enum.sort_by(& &1.datetime, {:asc, DateTime})

    {:ok, result}
  end

  defp community_messages_count_result(%{"error" => %{"message" => error_msg}}) do
    {:error, "Error fetching community messages count. Reason: #{error_msg}"}
  end

  defp community_messages_count_result(result) do
    Logger.error("Unexpected community messages count result: #{inspect(result)}")
    {:error, "Error fetching community messages count."}
  end

  defp metrics_hub_url() do
    Config.module_get(Sanbase.SocialData, :metricshub_url)
  end
end
