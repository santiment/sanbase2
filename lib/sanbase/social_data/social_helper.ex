defmodule Sanbase.SocialData.SocialHelper do
  alias Sanbase.Model.Project
  alias Sanbase.Model.Project.SocialVolumeQuery

  @sources [
    :telegram,
    :reddit,
    :twitter,
    :bitcointalk,
    :twitter_crypto,
    :twitter_news,
    :twitter_nft,
    :youtube_videos
  ]

  def sources(), do: @sources

  # NOTE 19.05.2022: Remove twitter because a combination of twitter and twitter_* source leads to exception in metric hub
  # the values for the twitter source are actually the sum of values for twitter_crypto and twitter_news sources
  def sources_total_string(), do: @sources |> Enum.reject(&(&1 == :twitter)) |> Enum.join(",")

  def social_metrics_selector_handler(%{slug: slugs}) when is_list(slugs) do
    {:error, "Social Metrics cannot work with list of slugs."}
  end

  def social_metrics_selector_handler(%{slug: slug}) when is_binary(slug) do
    slug
    |> Project.by_slug(only_preload: [:social_volume_query])
    |> case do
      %Project{social_volume_query: %{query: query, autogenerated_query: autogen_query}}
      when not is_nil(query) or not is_nil(autogen_query) ->
        {:ok, query || autogen_query}

      %Project{} = project ->
        {:ok, SocialVolumeQuery.default_query(project)}

      _ ->
        {:error, "Invalid slug"}
    end
  end

  def social_metrics_selector_handler(%{text: search_text}) do
    {:ok, search_text}
  end

  def social_metrics_selector_handler(_args) do
    {:error, "Invalid argument please input a slug or search_text"}
  end

  def split_by_source(str) do
    get_first_part = fn splitter, binary ->
      String.split(binary, splitter) |> hd |> String.trim_trailing("_")
    end

    source =
      (sources() ++ [:total])
      |> Enum.map(fn source -> Atom.to_string(source) end)
      |> Enum.find(&String.ends_with?(str, &1))

    type = get_first_part.(source, str)

    {type, source}
  end
end
