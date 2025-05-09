defmodule Sanbase.Project.Selector do
  @moduledoc """
  Module that is used for transforming selector from user-facing facing to the
  internal format.
  """

  require Application

  # This module exposes a single valid_slug?/1 function that returns true/false
  @available_slugs_module Application.compile_env(
                            :sanbase,
                            :available_slugs_module
                          )

  def args_to_raw_selector(%{slug: slug}), do: %{slug: slug}
  def args_to_raw_selector(%{slugs: slugs}), do: %{slug: slugs}
  def args_to_raw_selector(%{word: word}), do: %{word: word}

  # Only rename the key so the rest of the arguments are not lost
  def args_to_raw_selector(%{selector: %{slugs: _} = selector}),
    do: Sanbase.MapUtils.rename_key(selector, :slugs, :slug)

  def args_to_raw_selector(%{selector: %{} = selector}), do: selector
  def args_to_raw_selector(_), do: %{}

  @doc ~s"""
  Resolve the arguments to a selector of slugs. If the selector is already
  defined as a list of slugs, this list is returned.

  For example if the arguments contain %{selector: %{watchlistId: 1}} this will be
  resolved to %{selector: %{slug: ["slug1", "slug2", ...]}} where the list contains all
  the slugs from the watchlist.

  ## Options
    - use_process_dictionary: if true, the selector will be cached in the process dictionary
      for faster access. This is useful when the selector is used multiple times in the same
      request. This is the case when first computing the complexity and then fetching the data
      in getMetric's timeseries data API calls.
      Some watchlists can be defined as a screener and to compute the list of slugs a clickhouse
      database query should be made which returns all assets based on some condition.
      More complex screeners can be constructed as intersection or union of many such DB calls,
      making them slow to compute. So caching them in the process dictionary is a good idea.
  """
  @spec args_to_selector(map(), Keyword.t()) :: map()
  def args_to_selector(args, opts \\ []) do
    selector = args |> args_to_raw_selector()

    if Keyword.get(opts, :use_process_dictionary, false) do
      if result = Process.get({:args_to_selector, selector}) do
        result
      else
        result = do_args_to_selector(selector)
        Process.put({:args_to_selector, selector}, result)
        result
      end
    else
      do_args_to_selector(selector)
    end
  end

  # Private functions

  defp do_args_to_selector(raw_selector) do
    with {:ok, selector} <- transform_selector(raw_selector),
         {:ok, selector} <- maybe_ignore_slugs(selector),
         # TEMP 02.02.2023: Handle ripple -> xrp rename
         {:ok, selector} <- temp_replace_slugs(selector),
         true <- valid_selector?(selector) do
      {:ok, selector}
    end
  end

  defp valid_selector?(%{slug: nil}) do
    {:error, "The slug or slugs arguments must not be null."}
  end

  defp valid_selector?(%{slug: slug}) when is_binary(slug) do
    case @available_slugs_module.valid_slug?(slug) do
      true -> true
      false -> {:error, "The slug #{inspect(slug)} is not an existing slug."}
    end
  end

  # The check will make one ETS call per slug. It will be executed only for small
  # list of slugs (less than 10 slugs)
  defp valid_selector?(%{slug: slugs})
       when is_list(slugs) and length(slugs) < 10 do
    # If all of the slugs are valid return `true`. Return {:error, error} otherwise.
    slugs
    |> Enum.find_value(true, fn slug ->
      case @available_slugs_module.valid_slug?(slug) do
        true -> false
        false -> {:error, "The slug #{inspect(slug)} is not an existing slug."}
      end
    end)
  end

  defp valid_selector?(%{} = map) when map_size(map) == 0 do
    {:error,
     "The selector must have at least one field provided." <>
       "The available selector fields for a metric are listed in the metadata's availableSelectors field."}
  end

  defp valid_selector?(_), do: true

  defp transform_selector(%{market_segments: market_segments} = selector) do
    slugs =
      Sanbase.Project.List.by_market_segment_all_of(market_segments)
      |> Enum.map(& &1.slug)

    {:ok, Map.put(selector, :slug, slugs)}
  end

  defp transform_selector(%{ecosystems: ecosystems} = selector) do
    with {:ok, projects} <-
           Sanbase.Ecosystem.get_projects_by_ecosystem_names(ecosystems, combinator: :all_of) do
      slugs = projects |> Enum.map(& &1.slug)

      {:ok, Map.put(selector, :slug, slugs)}
    end
  end

  defp transform_selector(%{contract_address: contract_address} = selector) do
    slugs =
      Sanbase.Project.List.by_contracts(List.wrap(contract_address))
      |> Enum.map(& &1.slug)

    {:ok, Map.put(selector, :slug, slugs)}
  end

  defp transform_selector(%{watchlist_id: watchlist_id} = selector)
       when is_integer(watchlist_id) do
    with {:ok, watchlist} <- Sanbase.UserList.by_id(watchlist_id, []) do
      case Sanbase.UserList.get_slugs(watchlist) do
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

  defp temp_replace_slugs(selector) do
    selector =
      case selector do
        %{slug: "ripple"} ->
          Map.put(selector, :slug, "xrp")

        %{slug: list} when is_list(list) ->
          Map.update!(selector, :slug, &replace_in_list(&1, "ripple", "xrp"))

        %{slugs: list} when is_list(list) ->
          Map.update!(selector, :slugs, &replace_in_list(&1, "ripple", "xrp"))

        _ ->
          selector
      end

    {:ok, selector}
  end

  defp replace_in_list(list, old, new) do
    Enum.map(list, fn
      ^old -> new
      val -> val
    end)
  end
end
