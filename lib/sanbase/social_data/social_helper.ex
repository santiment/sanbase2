defmodule Sanbase.SocialData.SocialHelper do
  @sources [:telegram, :professional_traders_chat, :reddit, :discord, :twitter, :bitcointalk]

  def sources(), do: @sources

  def social_metrics_selector_handler(%{slug: slugs}) when is_list(slugs) do
    {:error, "Social Metrics cannot work with list of slugs."}
  end

  def social_metrics_selector_handler(%{slug: slug}) when is_binary(slug) do
    # We let metricshub ask sanbase back for the social volume query
    # This is done so that the social volume query that requires all projects is taken
    # This will leverage the caching, so it won't be that slow
    {:ok, %{slug: slug}}
  end

  def social_metrics_selector_handler(%{text: search_text}) do
    {:ok, %{text: search_text}}
  end

  def social_metrics_selector_handler(_args) do
    {:error, "Invalid argument please input a slug or search_text"}
  end

  def handle_search_term(%{slug: slug}) do
    {"slug", slug}
  end

  def handle_search_term(%{text: search_text}) do
    {"search_text", search_text |> URI.encode()}
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
