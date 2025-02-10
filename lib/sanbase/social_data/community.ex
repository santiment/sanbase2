defmodule Sanbase.SocialData.Community do
  @moduledoc false
  import Sanbase.Utils.ErrorHandling

  alias Sanbase.Project
  alias Sanbase.Utils.Config

  require Mockery.Macro

  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  @recv_timeout 15_000
  @sources [:telegram]

  def community_messages_count(selector, from, to, interval, source) when source in [:all, "all", :total, "total"] do
    result =
      @sources
      |> Sanbase.Parallel.flat_map(
        fn source ->
          {:ok, result} = community_messages_count(selector, from, to, interval, source)
          result
        end,
        max_concurrency: 4
      )
      |> Sanbase.Utils.Transform.sum_by_datetime(:mentions_count)

    {:ok, result}
  end

  def community_messages_count(%{slug: slug}, from, to, interval, source) do
    slug
    |> community_messages_count_request(from, to, interval, to_string(source))
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        community_messages_count_result(result)

      {:ok, %HTTPoison.Response{status_code: status}} ->
        warn_result("Error status #{status} fetching community messages count for project #{slug}")

      {:error, %HTTPoison.Error{} = error} ->
        error_result("Cannot fetch community messages count data for project #{slug}: #{HTTPoison.Error.message(error)}")
    end
  end

  def community_messages_count(argument) do
    {:error, "Invalid argument for community_messages_count #{inspect(argument)}"}
  end

  defp source_to_indicator(<<"telegram", _::binary>>), do: "telegram_discussion_overview"

  defp community_messages_count_request(slug, from, to, interval, source) do
    url = "#{tech_indicators_url()}/indicator/#{source_to_indicator(source)}"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"project", "#{Project.ticker_by_slug(slug)}_#{slug}"},
        {"datetime_from", DateTime.to_unix(from)},
        {"datetime_to", DateTime.to_unix(to)},
        {"interval", interval}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp community_messages_count_result(result) do
    result =
      Enum.map(result, fn
        %{"timestamp" => timestamp, "mentions_count" => mentions_count} ->
          %{
            datetime: DateTime.from_unix!(timestamp),
            mentions_count: mentions_count
          }
      end)

    {:ok, result}
  end

  defp tech_indicators_url do
    Config.module_get(Sanbase.TechIndicators, :url)
  end
end
