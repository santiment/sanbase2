defmodule SanbaseWeb.Graphql.Resolvers.ElasticsearchResolver do
  def stats(_root, %{from: from, to: to}, _resolution) do
    {:ok, Sanbase.Elasticsearch.stats(from, to)}
  end
end
