defmodule Sanbase.Model.Project.Selector do
  @moduledoc """
  Module that is used for transforming selector from user-facing facing to the
  internal format.
  """

  require Application

  # This module exposes a single valid_slug?/1 function that returns true/false
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
  defp valid_selector?(%{slug: slugs}) when is_list(slugs) and length(slugs) < 10 do
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
      Sanbase.Model.Project.List.by_market_segment_all_of(market_segments)
      |> Enum.map(& &1.slug)

    {:ok, Map.put(selector, :slug, slugs)}
  end

  defp transform_selector(%{contract_address: contract_address} = selector) do
    slugs =
      Sanbase.Model.Project.List.by_contracts(List.wrap(contract_address))
      |> Enum.map(& &1.slug)

    {:ok, Map.put(selector, :slug, slugs)}
  end

  defp transform_selector(%{watchlist_id: watchlist_id} = selector)
       when is_integer(watchlist_id) do
    with {:ok, watchlist} <- Sanbase.UserList.by_id(watchlist_id) do
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
end
