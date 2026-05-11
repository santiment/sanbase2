defmodule SanbaseWeb.Graphql.Schema.MajorTopicsQueries do
  @moduledoc false
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.MajorTopicsResolver

  object :major_topics_queries do
    @desc """
    Returns the most recent moderator-published "major topics" batch — a weekly
    snapshot of crypto-twitter narratives. The shape mirrors the existing
    `social-trends` static dataset: a shared `labels` list (dd.mm.yy) and one
    `dataset` per narrative with values aligned to those labels.
    """
    field :get_latest_major_topics, :major_topics_batch do
      meta(access: :free)

      cache_resolve(&MajorTopicsResolver.get_latest_published/3, ttl: 600)
    end
  end
end
