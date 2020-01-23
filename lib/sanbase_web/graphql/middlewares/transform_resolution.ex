defmodule SanbaseWeb.Graphql.Middlewares.TransformResolution do
  @moduledoc """

  """
  @behaviour Absinthe.Middleware
  alias Absinthe.Resolution

  def call(%Resolution{} = resolution, _opts) do
    %{context: context, definition: definition} = resolution

    case definition.name |> Macro.underscore() |> String.to_existing_atom() do
      :get_metric ->
        %{arguments: %{metric: metric}} = resolution
        elem = {:get_metric, metric}

        %Resolution{
          resolution
          | context: Map.update(context, :__get_query_name_arg__, [elem], &[elem | &1])
        }

      :get_anomaly ->
        %{arguments: %{anomaly: anomaly}} = resolution
        elem = {:get_anomaly, anomaly}

        %Resolution{
          resolution
          | context: Map.update(context, :__get_query_name_arg__, [elem], &[elem | &1])
        }

      _ ->
        resolution
    end
  end
end
