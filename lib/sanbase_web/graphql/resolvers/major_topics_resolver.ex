defmodule SanbaseWeb.Graphql.Resolvers.MajorTopicsResolver do
  @moduledoc false

  alias Sanbase.MajorTopics
  alias Sanbase.MajorTopics.BatchSerializer

  def get_latest_published(_root, _args, _resolution) do
    case MajorTopics.latest_published_batch() do
      nil -> {:ok, nil}
      batch -> {:ok, BatchSerializer.to_payload(batch)}
    end
  end
end
