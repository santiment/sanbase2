defmodule Sanbase.SocialData.SampleDocuments do
  @moduledoc """
  A stratified sample of raw social messages about an asset, from metrics-hub's
  `/sample_documents`, plus a stats block computed over all matching messages.

  Each message has a `stratum`: `head` (top by engagement), `random` (unbiased base) or
  `poles` (oversampled bullish/bearish extremes).
  """

  alias Sanbase.SocialData.MetricsHubClient

  # The default is the crowd sources; `twitter` means all the twitter indices.
  @default_sources ~w(telegram reddit twitter_crypto 4chan bitcointalk farcaster)
  @sources @default_sources ++ ~w(twitter twitter_news twitter_nft)
  @slug_regex ~r/^[a-z0-9-]+$/

  @type opts :: [
          from: String.t() | nil,
          to: String.t() | nil,
          sources: [String.t()] | nil,
          max_words: pos_integer() | nil
        ]

  @type error :: {:permanent | :transient | :unknown, String.t()}

  @doc "The source ids metrics-hub accepts."
  @spec sources() :: [String.t()]
  def sources(), do: @sources

  @doc "The sources sampled when none are given."
  @spec default_sources() :: [String.t()]
  def default_sources(), do: @default_sources

  @doc """
  Sample messages about `asset`: a project slug (e.g. `bitcoin`) or a free search word.

  A slug-shaped `asset` is first queried as a slug; when that matches nothing it is
  retried as free text, as a project query can miss a name that is being discussed.

  Options:
    * `:from`, `:to` - ISO-8601 or Elasticsearch date math (`now-24h`). metrics-hub
      defaults to the last 24 hours.
    * `:sources` - source ids from `sources/0`. Defaults to the crowd sources:
      #{Enum.join(@default_sources, ", ")}.
    * `:max_words` - the max total words of the sampled texts. metrics-hub clamps it.
  """
  @spec sample(String.t(), opts()) :: {:ok, map()} | {:error, error()}
  def sample(asset, opts \\ []) do
    asset = String.trim(asset || "")

    with :ok <- validate_asset(asset),
         {:ok, body} <- base_body(opts) do
      slug = String.downcase(asset)

      if Regex.match?(@slug_regex, slug) do
        sample_slug(slug, asset, body)
      else
        body |> Map.put(:search_text, asset) |> fetch() |> finalize(:text_only)
      end
    end
  end

  defp sample_slug(slug, asset, body) do
    with {:ok, data} <- fetch(Map.put(body, :slug, slug)) do
      if total(data) == 0 do
        body |> Map.put(:search_text, asset) |> fetch() |> fallback_result(data, asset)
      else
        finalize({:ok, data})
      end
    end
  end

  defp fallback_result({:ok, text_data}, slug_data, asset) do
    if total(text_data) > 0 do
      note =
        "The project query for slug #{inspect(asset)} matched no messages; these results " <>
          "are a free-text search for #{inspect(asset)} instead."

      text_data
      |> update_in(["stats"], &Map.merge(&1, %{"query_mode" => "search_text", "note" => note}))
      |> then(&finalize({:ok, &1}))
    else
      finalize({:ok, slug_data})
    end
  end

  # The slug matched nothing and the retry failed: whether there is crowd data is unknown.
  defp fallback_result({:error, {kind, message}}, _slug_data, asset) do
    {:error,
     {kind,
      "Slug #{inspect(asset)} matched no messages and the free-text retry failed, so it " <>
        "is unknown whether there are messages about it. #{message}"}}
  end

  # `checked` says how the asset was queried, so an empty result's note is accurate:
  # `:slug_and_text` (a slug-shaped asset, retried as free text) or `:text_only`.
  defp finalize(result, checked \\ :slug_and_text)

  defp finalize({:ok, data}, checked) do
    result = %{"stats" => data["stats"], "messages" => data["messages"] || []}

    if total(data) == 0 and result["messages"] == [] do
      {:ok, Map.put(result, "note", empty_note(checked))}
    else
      {:ok, result}
    end
  end

  defp finalize({:error, _} = error, _checked), do: error

  defp empty_note(:slug_and_text) do
    "No social messages matched this asset in this window (checked as a project slug " <>
      "and as free text). There is no crowd data for it."
  end

  defp empty_note(:text_only) do
    "No social messages matched this text in this window. It was searched as free text " <>
      "only, because it is not shaped like a project slug: retry with the project's slug " <>
      "(e.g. `pepe`, `bitcoin-cash`) to also search by project."
  end

  defp validate_asset(""),
    do: {:error, {:permanent, "`asset` is required: a project slug or a search word."}}

  defp validate_asset(_asset), do: :ok

  defp base_body(opts) do
    with {:ok, sources} <- validate_sources(opts[:sources]) do
      body =
        %{
          max_words: opts[:max_words],
          from_timestamp: normalize_time(opts[:from]),
          to_timestamp: normalize_time(opts[:to]),
          sources: sources && Enum.join(sources, ",")
        }
        |> Map.reject(fn {_key, value} -> is_nil(value) end)

      {:ok, body}
    end
  end

  defp validate_sources(nil), do: {:ok, nil}
  defp validate_sources([]), do: {:ok, nil}

  defp validate_sources(sources) when is_list(sources) do
    sources = sources |> Enum.map(&normalize_source/1) |> Enum.uniq()

    case Enum.reject(sources, &(&1 in @sources)) do
      [] ->
        {:ok, sources}

      unknown ->
        {:error,
         {:permanent,
          "Unknown source(s) #{Enum.join(unknown, ", ")}. Valid sources: " <>
            Enum.join(@sources, ", ")}}
    end
  end

  # A JSON null in the list passes the schema; keep it and report it as unknown below.
  defp normalize_source(source) when is_binary(source),
    do: source |> String.trim() |> String.downcase()

  defp normalize_source(source), do: inspect(source)

  # Santiment-style date math (`utc_now-24h`) is `now-24h` in Elasticsearch.
  defp normalize_time(nil), do: nil

  defp normalize_time(time) when is_binary(time) do
    case String.trim(time) do
      "" -> nil
      time -> String.replace(time, "utc_now", "now")
    end
  end

  defp fetch(body) do
    case MetricsHubClient.post("/sample_documents", body) do
      {:ok, %{"stats" => stats} = data} when is_map(stats) -> {:ok, data}
      {:ok, data} -> MetricsHubClient.unexpected(data)
      {:error, _} = error -> error
    end
  end

  defp total(%{"stats" => %{"total_matching" => total}}) when is_number(total), do: trunc(total)

  defp total(%{"stats" => %{"total_matching" => total}}) when is_binary(total) do
    case Integer.parse(total) do
      {total, _} -> total
      :error -> 0
    end
  end

  defp total(_data), do: 0
end
