defmodule SanbaseWeb.Graphql.Resolvers.ElasticsearchResolver do
  def stats(_root, _args, _resolution) do
    {:ok, Sanbase.Elasticsearch.stats()}
  end
end