defmodule Sanbase.SocialData.SocialHelper do
  @moduledoc false
  alias Sanbase.Project
  alias Sanbase.Project.SocialVolumeQuery

  @sources [
    :"4chan",
    :telegram,
    :reddit,
    :twitter,
    :bitcointalk,
    :youtube_videos,
    :farcaster
  ]

  def sources, do: @sources
  def sources_total_string, do: "total"

  def replace_words_with_original_casing(result, words) do
    Enum.map(result, fn %{word: lowercase_word} = map ->
      original_word = Enum.find(words, fn w -> String.downcase(w) == lowercase_word end)

      Map.put(map, :word, original_word)
    end)
  end

  def social_metrics_selector_handler(%{slug: slugs}) when is_list(slugs) do
    {:error, "Social Metrics cannot work with list of slugs."}
  end

  def social_metrics_selector_handler(%{slug: slug}) when is_binary(slug) do
    slug
    |> Project.by_slug(preload: [:social_volume_query])
    |> case do
      %Project{social_volume_query: %{query: query, autogenerated_query: autogen_query}}
      when not is_nil(query) or not is_nil(autogen_query) ->
        {:ok, "search_text", query || autogen_query}

      %Project{} = project ->
        {:ok, "search_text", SocialVolumeQuery.default_query(project)}

      _ ->
        {:error, "Invalid slug"}
    end
  end

  def social_metrics_selector_handler(%{text: search_text}) do
    {:ok, "search_text", search_text}
  end

  def social_metrics_selector_handler(%{founders: founders}) do
    {:ok, "founders", Enum.join(founders, ",")}
  end

  def social_metrics_selector_handler(_args) do
    {:error, "Invalid argument please input a slug or search_text"}
  end

  @doc ~s"""
  Get a string balance_twitter and split it into two parts -- a source (twitter, telegram, etc.)
  and everything before the source
  """
  def split_by_source(str) do
    source =
      (sources() ++ [:total])
      |> Enum.map(&to_string/1)
      |> Enum.find(&String.ends_with?(str, &1))

    type = String.trim_trailing(str, "_#{source}")

    {type, source}
  end
end
