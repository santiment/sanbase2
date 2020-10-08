defmodule Sanbase.Metric.Selector do
  @available_slugs_module Application.compile_env(:sanbase, :available_slugs_module)

  def args_to_raw_selector(%{slug: slug}), do: %{slug: slug}
  def args_to_raw_selector(%{slugs: slugs}), do: %{slug: slugs}
  def args_to_raw_selector(%{word: word}), do: %{word: word}
  def args_to_raw_selector(%{selector: %{slugs: slugs}}), do: %{slug: slugs}
  def args_to_raw_selector(%{selector: %{} = selector}), do: selector
  def args_to_raw_selector(_), do: %{}

  def args_to_selector(args) do
    selector = args |> args_to_raw_selector()

    with {:ok, selector} <- transform_selector(selector),
         {:ok, selector} <- maybe_ignore_slugs(selector),
         true <- valid_selector?(selector) do
      {:ok, selector}
    end
  end

  # Private functions

  defp valid_selector?(%{slug: slug}) when is_binary(slug) do
    case @available_slugs_module.valid_slug?(slug) do
      true -> true
      false -> {:error, "The slug #{inspect(slug)} is not an existing slug."}
    end
  end

  defp valid_selector?(%{} = map) when map_size(map) == 0,
    do:
      {:error,
       "The selector must have at least one field provided." <>
         "The available selector fields for a metric are listed in the metadata's availableSelectors field."}

  defp valid_selector?(_), do: true

  defp transform_selector(%{market_segments: market_segments} = selector) do
    slugs =
      Sanbase.Model.Project.List.by_market_segment_all_of(market_segments)
      |> Enum.map(& &1.slug)

    {:ok, Map.put(selector, :slug, slugs)}
  end

  defp transform_selector(%{watchlist_id: watchlist_id} = selector)
       when is_integer(watchlist_id) do
    case Sanbase.UserList.by_id(watchlist_id) do
      nil ->
        {:error, "Watchlist with id #{watchlist_id} does not exist."}

      watchlist ->
        case watchlist |> Sanbase.UserList.get_slugs() do
          {:ok, slugs} ->
            {:ok, Map.put(selector, :slug, slugs)}

          {:error, _error} ->
            {:error, "Cannot fetch slugs for watchlist with id #{watchlist_id}"}
        end
    end
  end

  defp transform_selector(%{watchlist_slug: watchlist_slug} = selector)
       when is_binary(watchlist_slug) do
    case Sanbase.UserList.by_slug(watchlist_slug) do
      nil ->
        {:error, "Watchlist with slug #{watchlist_slug} does not exist."}

      watchlist ->
        case watchlist |> Sanbase.UserList.get_slugs() do
          {:ok, slugs} ->
            {:ok, Map.put(selector, :slug, slugs)}

          {:error, _error} ->
            {:error, "Cannot fetch slugs for watchlist with slug #{watchlist_slug}"}
        end
    end
  end

  defp transform_selector(identifier), do: {:ok, identifier}

  defp maybe_ignore_slugs(%{ignored_slugs: [_ | _] = ignored_slugs, slug: slugs} = selector) do
    slugs = List.wrap(slugs) -- ignored_slugs
    {:ok, Map.put(selector, :slug, slugs)}
  end

  defp maybe_ignore_slugs(selector), do: {:ok, selector}
end
