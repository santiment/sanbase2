defmodule SanbaseWeb.Graphql.Middlewares.NormalizeMetricVersion do
  @moduledoc """
  Rewrite the `version` argument of `getMetric` from a name ("modern_pit:v1") to
  the canonical version ("2.1"). Runs first, so logging, access checks, cache
  keys and SQL all see the canonical version.
  """

  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution
  alias Sanbase.Metric.VersionAlias

  @impl Absinthe.Middleware
  def call(%Resolution{state: :resolved} = resolution, _opts), do: resolution

  def call(%Resolution{arguments: %{version: version}} = resolution, _opts)
      when is_binary(version) do
    case VersionAlias.to_version_num(version) do
      {:ok, version_num} ->
        %{resolution | arguments: Map.put(resolution.arguments, :version, version_num)}

      {:error, error} ->
        Resolution.put_result(resolution, {:error, error})
    end
  end

  def call(%Resolution{} = resolution, _opts), do: resolution
end
