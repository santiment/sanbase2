defmodule Sanbase.SocialData.SocialVolume do
  import Sanbase.Utils.ErrorHandling

  require Logger
  require Mockery.Macro
  alias Sanbase.Utils.Config

  alias Sanbase.SocialData.SocialHelper
  alias Sanbase.Project
  alias Sanbase.Clickhouse.NftTrade

  import Sanbase.Utils.Transform, only: [maybe_apply_function: 2]

  defp http_client, do: Mockery.Macro.mockable(HTTPoison)

  @recv_timeout 25_000
  def social_volume(selector, from, to, interval, source, opts \\ [])

  def social_volume(selector, from, to, interval, source, opts)
      when source in [:all, "all", :total, "total"] do
    social_volume(selector, from, to, interval, SocialHelper.sources_total_string(), opts)
  end

  def social_volume(%{contract_address: contract}, from, to, interval, source, opts)
      when is_binary(contract) do
    search_text =
      contract
      |> Sanbase.BlockchainAddress.to_internal_format()
      |> NftTrade.nft_search_text_by_contract()

    case search_text do
      text when is_binary(text) ->
        social_volume(%{text: text}, from, to, interval, source, opts)

      _ ->
        {:error, "Cannot fetch Social Volume for this contract: #{contract}"}
    end
  end

  def social_volume(%{words: words} = selector, from, to, interval, source, opts)
      when is_list(words) do
    transformed_words = Enum.reject(words, &(&1 == "***"))
    treat_word_as_lucene_query = Keyword.get(opts, :treat_word_as_lucene_query, false)

    transformed_words =
      case Keyword.get(opts, :treat_word_as_lucene_query, false) do
        false ->
          transformed_words
          |> Enum.map(fn word ->
            word
            |> String.downcase()
            |> URI.encode_www_form()
          end)

        true ->
          Enum.map(transformed_words, fn word ->
            word
            |> URI.encode_www_form()
          end)
      end

    selector = %{selector | words: transformed_words}

    social_volume_list_request(selector, from, to, interval, source, opts)
    |> handle_words_social_volume_response(selector)
    |> maybe_apply_function(fn result ->
      if treat_word_as_lucene_query do
        result
      else
        # If the words are **not** treated as lucene syntax (the default behaviour)
        # they are lowercased before they are sent to metricshub. Because of that
        # we need to properly map the result of metricshub back to the original casing
        # of the word that came from the API call
        SocialHelper.replace_words_with_original_casing(result, words)
      end
    end)
  end

  def social_volume(selector, from, to, interval, source, opts) do
    social_volume_request(selector, from, to, interval, source, opts)
    |> handle_response(selector)
  end

  defp handle_response(response, selector) do
    case response do
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

  defp handle_words_social_volume_response(response, %{words: words} = selector) do
    case response do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body
        |> Jason.decode!()
        |> Map.fetch!("data")
        |> maybe_format_response(words)
        |> Enum.map(fn {word, %{} = timeseries} ->
          %{
            word: URI.decode_www_form(word),
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

  defp maybe_format_response(_data, [] = _words), do: %{}

  defp maybe_format_response(data, words) do
    # Metricshub returns different format when a single word is provided.
    # Unify both responses so the result is handled easily
    # When more than 1 word is returned, the result is map where the word
    # is the key.
    # %{
    #   "data" => %{
    #     "bitcoin" => %{
    #       "2022-10-05T00:00:00Z" => 1401
    #     },
    #     "ethereum" => %{
    #       "2022-10-04T12:00:00Z" => 576,
    #     }
    #   }
    # }
    #
    # When only 1 word is used, there is no word as key.
    # %{
    #   "data" => %{
    #     "2022-10-05T00:00:00Z" => 1399
    #   }
    # }
    case Map.values(data) |> List.first() do
      %{} ->
        data

      _ ->
        [word] = words
        %{word => data}
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

      options =
        [
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
