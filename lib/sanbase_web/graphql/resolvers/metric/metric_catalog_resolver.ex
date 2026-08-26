defmodule SanbaseWeb.Graphql.Resolvers.MetricCatalogResolver do
  @moduledoc false

  alias Sanbase.Metric.Catalog.Directory

  def get_metric_catalog(_root, args, _resolution) do
    {:ok, Directory.metrics(to_opts(args))}
  end

  def get_metric_catalog_categories(_root, args, _resolution) do
    {:ok, Directory.categories(to_opts(args))}
  end

  defp to_opts(args) do
    [
      search_term: Map.get(args, :search_term),
      categories: Map.get(args, :categories),
      groups: Map.get(args, :groups),
      include_deprecated: Map.get(args, :include_deprecated, false),
      page: Map.get(args, :page),
      page_size: Map.get(args, :page_size)
    ]
  end
end
