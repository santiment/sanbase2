defmodule SanbaseWeb.Graphql.Middlewares.NormalizeMetricVersion do
  @moduledoc """
  Translate the `version` argument of `getMetric` from a version name
  ("modern_pit:v1") into the canonical version ("2.1").

  Runs before every other middleware and the resolver, so API-call logging
  (`TransformResolution`), the default/Experimental checks, `resolution.source`,
  the GraphQL cache key and the SQL all see the canonical version. A name and
  its number are one cache entry and one log line.

  Input that does not look like a name passes through untouched - see
  `Sanbase.Metric.VersionAlias.to_version_num/2`.
  """

  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution
  alias Sanbase.Metric.VersionAlias

  def call(%Resolution{state: :resolved} = resolution, _opts), do: resolution

  def call(%Resolution{arguments: %{metric: metric, version: version}} = resolution, _opts)
      when is_binary(metric) and is_binary(version) do
    case VersionAlias.to_version_num(metric, version) do
      {:ok, version_num} ->
        %{resolution | arguments: Map.put(resolution.arguments, :version, version_num)}

      {:error, error} ->
        Resolution.put_result(resolution, {:error, error})
    end
  end

  def call(%Resolution{} = resolution, _opts), do: resolution
end
