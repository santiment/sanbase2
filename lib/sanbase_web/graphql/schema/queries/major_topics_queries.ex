defmodule SanbaseWeb.Graphql.Schema.MajorTopicsQueries do
  @moduledoc false
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.MajorTopicsResolver

  object :major_topics_queries do
    @desc """
    Fetch a moderator-published "major topics" batch — a snapshot of
    crypto-twitter narratives over a fixed interval (week or day). The shape
    mirrors the existing `social-trends` static dataset: a shared `labels` list
    (dd.mm.yy) and one `dataset` per narrative with values aligned to those
    labels.

    Frontend pagination flow:
      1. First load — call with `granularity` only; the latest published batch
         for that granularity is returned.
      2. Each response carries `previousIntervalStart` and `nextIntervalStart`
         cursors. To navigate, pass either as the `intervalStart` argument on
         the next call.

    Returns `null` when no batch exists for the given `(granularity,
    intervalStart)` pair, or when nothing has been published yet for the
    requested granularity.
    """
    field :major_topics_batch, :major_topics_batch do
      arg(:granularity, non_null(:topic_granularity))

      @desc "Optional `intervalStart` cursor. Omit to fetch the latest published batch."
      arg(:interval_start, :date)

      meta(access: :free)

      cache_resolve(&MajorTopicsResolver.get_major_topics_batch/3, ttl: 600)
    end

    @desc """
    Deprecated. Equivalent to `majorTopicsBatch(granularity: WEEK)`. Will be
    removed once frontends migrate.
    """
    field :get_latest_major_topics, :major_topics_batch do
      meta(access: :free)

      cache_resolve(&MajorTopicsResolver.get_latest_published/3, ttl: 600)
    end
  end
end
