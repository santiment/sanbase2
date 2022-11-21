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
    |> do_call(resolution)
  end

  defp do_call(:get_metric, %{context: context} = resolution) do
    %{arguments: %{metric: metric}} = resolution
    selectors = get_selectors(resolution)
    elem = {:get_metric, metric, selectors}

    %Resolution{
      resolution
      | context: Map.update(context, :__get_query_name_arg__, [elem], &[elem | &1])
    }
  end

  defp do_call(:get_signal, %{context: context} = resolution) do
    %{arguments: %{signal: signal}} = resolution
    selectors = get_selectors(resolution)
    elem = {:get_signal, signal, selectors}

    %Resolution{
      resolution
      | context: Map.update(context, :__get_query_name_arg__, [elem], &[elem | &1])
    }
  end

  defp do_call(query_field, resolution) do
    resolution
  end

  @fields_with_selector ["timeseriesData", "timeseriesDataPerSlug", "aggregatedTimeseriesData"]
  defp get_selectors(resolution) do
    resolution.definition.selections
    |> Enum.map(fn %{name: name} = field ->
      selector =
        case Inflex.camelize(name, :lower) do
          name when name in @fields_with_selector ->
            argument_data_to_selector(field.argument_data)

          name ->
            nil
        end
    end)
  end

  defp argument_data_to_selector(%{selector: selector}), do: selector
  defp argument_data_to_selector(%{slug: slug}), do: %{slug: slug}
  defp argument_data_to_selector(_), do: nil
end
