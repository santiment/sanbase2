defmodule SanbaseWeb.Graphql.Middlewares.TransformResolution do
  @moduledoc """
  Update the :__get_query_name_arg__ in the context in case the query is
  get_metric, get_signal or get_anomly.
  """

  @behaviour Absinthe.Middleware
  alias Absinthe.Resolution

  def call(%Resolution{} = resolution, _opts) do
    %{definition: definition} = resolution

    definition.name
    |> Macro.underscore()
    |> String.to_existing_atom()
    |> do_call(definition.alias, resolution)
  end

  defp do_call(:get_metric, alias, %Resolution{context: context} = resolution) do
    %{arguments: %{metric: metric}} = resolution
    selectors = get_selectors(resolution)
    # In case of no alias, use the query name as alias. It is guaranteed that if there are two
    # of the same queries in a document, at least one of them will have an alias,
    # otherwise we get name collision.
    elem = {:get_metric, alias || "getMetric", metric, selectors}

    %{resolution | context: Map.update(context, :__get_query_name_arg__, [elem], &[elem | &1])}
  end

  defp do_call(:get_signal, alias, %Resolution{context: context} = resolution) do
    %{arguments: %{signal: signal}} = resolution
    selectors = get_selectors(resolution)
    # In case of no alias, use the query name as alias. It is guaranteed that if there are two
    # of the same queries in a document, at least one of them will have an alias,
    # otherwise we get name collision.
    elem = {:get_signal, alias || "getSignal", signal, selectors}

    %{resolution | context: Map.update(context, :__get_query_name_arg__, [elem], &[elem | &1])}
  end

  defp do_call(_query_field, _alias, %Resolution{} = resolution) do
    resolution
  end

  @fields_with_selector [
    "timeseriesData",
    "timeseriesDataJson",
    "timeseriesDataPerSlug",
    "timeseriesDataPerSlugJson",
    "aggregatedTimeseriesData"
  ]
  defp get_selectors(%Resolution{} = resolution) do
    resolution.definition.selections
    |> Enum.map(fn %{name: name} = field ->
      case Inflex.camelize(name, :lower) do
        name when name in @fields_with_selector ->
          argument_data_to_selector(field.argument_data)

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # In some cases users can provide lists of slugs that have 50-100-200 slugs inside
  # This would take a lot of resources to store, so it's redacted.
  defp argument_data_to_selector(%{selector: selector}), do: selector
  defp argument_data_to_selector(%{slug: slugs}) when length(slugs) <= 5, do: %{slug: slugs}
  defp argument_data_to_selector(%{slug: [_ | _]}), do: %{slug: "<long_slugs_list>"}
  defp argument_data_to_selector(%{slug: slug}), do: %{slug: slug}
  defp argument_data_to_selector(_), do: nil
end
