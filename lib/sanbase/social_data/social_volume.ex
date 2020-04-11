defmodule Sanbase.SocialData.SocialVolume do
  import Sanbase.Utils.ErrorHandling

  require Logger
  require Sanbase.Utils.Config, as: Config

  alias Sanbase.Model.Project
  alias Sanbase.Model.Project.SocialVolumeQuery

  require Mockery.Macro
  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  @recv_timeout 25_000
  @sources [:telegram, :professional_traders_chat, :reddit, :discord]

  def social_volume(selector, from, to, interval, source)
      when source in [:all, "all", :total, "total"] do
    result =
      @sources
      |> Sanbase.Parallel.flat_map(
        fn source ->
          {:ok, result} = social_volume(selector, from, to, interval, source)
          result
        end,
        max_concurrency: 4
      )
      |> Sanbase.Utils.Transform.sum_by_datetime(:mentions_count)

    {:ok, result}
  end

  def social_volume(selector, from, to, interval, source) do
    social_volume_request(selector, from, to, interval, source)
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        social_volume_result(result)

      {:ok, %HTTPoison.Response{status_code: status}} ->
        warn_result("Error status #{status} fetching social volume")

      {:error, %HTTPoison.Error{} = error} ->
        error_result("Cannot fetch social volume data: #{HTTPoison.Error.message(error)}")
    end
  end

  def social_volume_projects() do
    social_volume_projects_request()
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        social_volume_projects_result(result)

      {:ok, %HTTPoison.Response{status_code: status}} ->
        warn_result("Error status #{status} fetching social volume projects.")

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch social volume projects data: #{HTTPoison.Error.message(error)}"
        )
    end
  end

  defp social_volume_selector_handler(%{slug: slug}) do
    query =
      slug
      |> Project.by_slug(only_preload: [:social_volume_query])
      |> case do
        %Project{social_volume_query: %Sanbase.Model.Project.SocialVolumeQuery{query: query_text}}
        when not is_nil(query_text) ->
          query_text

        %Project{} = project ->
          SocialVolumeQuery.default_query(project)

        _ ->
          {:error, "Invalid slug"}
      end

    {"search_text", query}
  end

  defp social_volume_selector_handler(%{search_text: search_text}) do
    {"search_text", search_text}
  end

  defp social_volume_selector_handler(args) do
    {:error, "Invalid argument for social_volume, please input a slug or search_text"}
  end

  defp social_volume_request(selector, from, to, interval, source) do
    slug_or_search_text_string = social_volume_selector_handler(selector)

    url = "#{metrics_hub_url()}/social_volume?"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        slug_or_search_text_string,
        {"from_timestamp", from},
        {"to_timestamp", to},
        {"interval", interval},
        {"source", source}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp social_volume_result(%{"data" => map}) do
    map =
      Enum.map(map, fn {datetime, value} ->
        %{
          datetime: Sanbase.DateTimeUtils.from_iso8601!(datetime),
          mentions_count: value
        }
      end)

    {:ok, map}
  end

  defp social_volume_projects_request() do
    url = "#{tech_indicators_url()}/indicator/social_volume_projects"

    options = [recv_timeout: @recv_timeout]

    http_client().get(url, [], options)
  end

  defp social_volume_projects_result(result) do
    result =
      result
      |> Enum.map(fn ticker_slug ->
        [_ticker, slug] = String.split(ticker_slug, "_", parts: 2)
        slug
      end)

    {:ok, result}
  end

  defp tech_indicators_url() do
    Config.module_get(Sanbase.TechIndicators, :url)
  end

  defp metrics_hub_url() do
    Config.module_get(Sanbase.SocialData, :metricshub_url)
  end
end
