defmodule Sanbase.SocialData.SocialVolume do
  import Sanbase.Utils.ErrorHandling

  require Logger
  require Mockery.Macro
  require Sanbase.Utils.Config, as: Config

  alias Sanbase.SocialData.SocialHelper
  alias Sanbase.Model.Project
  alias Sanbase.ClickhouseRepo

  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  @recv_timeout 25_000
  def social_volume(selector, from, to, interval, source, opts \\ [])

  def social_volume(selector, from, to, interval, source, opts)
      when source in [:all, "all", :total, "total"] do
    sources_string = SocialHelper.sources() |> Enum.join(",")

    social_volume(selector, from, to, interval, sources_string, opts)
  end

  def social_volume(%{contract_address: contract} = selector, from, to, interval, source, opts)
      when is_binary(contract) do
    search_text = search_text_by_contract(contract)

    case search_text do
      text when is_binary(text) ->
        social_volume(%{text: text}, from, to, interval, source, opts)

      _ ->
        {:error, "Cannot fetch Social Volume for this contract: #{contract}"}
    end
  end

  def social_volume(%{words: words} = selector, from, to, interval, source, opts)
      when is_list(words) do
    social_volume_list_request(selector, from, to, interval, source, opts)
    |> handle_list_response(selector)
  end

  def social_volume(selector, from, to, interval, source, opts) do
    social_volume_request(selector, from, to, interval, source, opts)
    |> handle_response(selector)
  end

  defp handle_response(response, selector) do
    response
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body
        |> Jason.decode!()
        |> Map.get("data")
        |> social_volume_result()
        |> wrap_ok()

      {:ok, %HTTPoison.Response{status_code: status}} ->
        warn_result("Error status #{status} fetching social volume for #{inspect(selector)}")

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch social volume data for #{inspect(selector)}: #{HTTPoison.Error.message(error)}"
        )
    end
  end

  defp handle_list_response(response, selector) do
    case response do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body
        |> Jason.decode!()
        |> Map.fetch!("data")
        |> Enum.map(fn {word, timeseries} ->
          %{
            word: word,
            timeseries_data: social_volume_result(timeseries)
          }
        end)
        |> wrap_ok()

      {:ok, %HTTPoison.Response{status_code: status}} ->
        warn_result("Error status #{status} fetching social volume for #{inspect(selector)}")

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch social volume data for #{inspect(selector)}: #{HTTPoison.Error.message(error)}"
        )

      {:error, error} ->
        {:error, error}
    end
  end

  def social_volume_projects() do
    projects = Enum.map(Project.List.projects(), fn %Project{slug: slug} -> slug end)

    {:ok, projects}
  end

  defp social_volume_list_request(%{words: words}, from, to, interval, source, opts) do
    url = Path.join([metrics_hub_url(), opts_to_metric(opts)])

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"search_texts", Enum.join(words, ",")},
        {"from_timestamp", from |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
        {"to_timestamp", to |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
        {"interval", interval},
        {"source", source}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp social_volume_request(selector, from, to, interval, source, opts) do
    with {:ok, search_text} <- SocialHelper.social_metrics_selector_handler(selector) do
      url = Path.join([metrics_hub_url(), opts_to_metric(opts)])

      options = [
        recv_timeout: @recv_timeout,
        params: [
          {"search_text", search_text},
          {"from_timestamp", from |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
          {"to_timestamp", to |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
          {"interval", interval},
          {"source", source}
        ]
      ]

      http_client().get(url, [], options)
    end
  end

  defp social_volume_result(map) do
    Enum.map(map, fn {datetime, value} ->
      %{
        datetime: Sanbase.DateTimeUtils.from_iso8601!(datetime),
        mentions_count: value
      }
    end)
    |> Enum.sort_by(& &1.datetime, {:asc, DateTime})
  end

  def search_text_by_contract(contract, blockchain \\ "ethereum") do
    query = """
    SELECT dictGet('default.labels_dict', 'search_text', label_id)
    FROM
    (
        SELECT labels
        FROM default.current_labels
        WHERE (blockchain = ?1) AND (address = lower(?2))
    )
    ARRAY JOIN labels AS label_id
    WHERE dictGet('default.labels_dict', 'key', label_id) = 'name'
    """

    args = [blockchain, contract]

    case ClickhouseRepo.query_transform(query, args, fn [search_term] -> search_term end) do
      {:ok, [search_term]} when not is_nil(search_term) -> search_term
      _ -> nil
    end
  end

  def opts_to_metric(opts) do
    case Keyword.get(opts, :metric) do
      "nft_social_volume" -> "nft_collections_social_volume"
      _ -> "social_volume"
    end
  end

  defp metrics_hub_url() do
    Config.module_get(Sanbase.SocialData, :metricshub_url)
  end

  defp wrap_ok(result), do: {:ok, result}
end
