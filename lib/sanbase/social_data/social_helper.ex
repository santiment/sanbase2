defmodule Sanbase.SocialData.SocialHelper do
  alias Sanbase.Model.Project
  alias Sanbase.Model.Project.SocialVolumeQuery

  def social_metrics_selector_handler(%{slug: slug}) do
    slug
    |> Project.by_slug(only_preload: [:social_volume_query])
    |> case do
      %Project{social_volume_query: %{query: query_text}}
      when not is_nil(query_text) ->
        {:ok, query_text}

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
end
