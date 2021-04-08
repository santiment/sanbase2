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
    elem = {:get_metric, metric}

    %Resolution{
      resolution
      | context: Map.update(context, :__get_query_name_arg__, [elem], &[elem | &1])
    }
  end

  defp do_call(:get_signal, %{context: context} = resolution) do
    %{arguments: %{signal: signal}} = resolution
    elem = {:get_signal, signal}

    %Resolution{
      resolution
      | context: Map.update(context, :__get_query_name_arg__, [elem], &[elem | &1])
    }
  end

  defp do_call(:get_anomaly, %{context: context} = resolution) do
    %{arguments: %{anomaly: anomaly}} = resolution
    elem = {:get_anomaly, anomaly}

    %Resolution{
      resolution
      | context: Map.update(context, :__get_query_name_arg__, [elem], &[elem | &1])
    }
  end

  defp do_call(_, resolution), do: resolution
end
