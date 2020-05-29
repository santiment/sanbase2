defmodule SanbaseWeb.Graphql.Resolvers.ElasticsearchResolver do
  require Logger

  def stats(_root, %{from: from, to: to}, _resolution) do
    {:ok, Sanbase.Elasticsearch.stats(from, to)}
  rescue
    error ->
      Logger.error("Error getting Elasticearch stats. Reason: #{inspect(error)}")
      {:error, "Error getting Elasticearch stats"}
  end
end
