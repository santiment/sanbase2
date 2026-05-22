defmodule SanbaseWeb.Graphql.MajorTopicsTypes do
  @moduledoc false
  use Absinthe.Schema.Notation

  @desc "Granularity of a major-topics batch."
  enum :topic_granularity do
    value(:day, as: "day")
    value(:week, as: "week")
  end

  object :major_topic_dataset do
    field(:label, non_null(:string))

    @desc "Top 5 words by score, comma-separated (e.g. \"emails,pages,file,doj,epsteins\")."
    field(:top_words, non_null(:string))

    field(:description, non_null(:string))

    @desc "Per-label values, aligned 1:1 with the parent batch `labels` list. Missing observations are 0."
    field(:data, non_null(list_of(non_null(:float))))

    field(:is_crypto_relevant, non_null(:boolean))
  end

  object :major_topics_batch do
    field(:granularity, non_null(:topic_granularity))
    field(:interval_start, non_null(:date))
    field(:interval_end, non_null(:date))
    field(:published_at, :datetime)

    @desc "X-axis labels formatted as `dd.mm.yy`, in chronological order. Aligned with each dataset's `data` list."
    field(:labels, non_null(list_of(non_null(:string))))

    field(:datasets, non_null(list_of(non_null(:major_topic_dataset))))

    @desc """
    `intervalStart` of the published batch whose start is nearest to one
    pagination step before the current batch. Step size depends on `granularity`
    (7 days for WEEK, 1 day for DAY). `null` when no earlier batch is available.
    Pass it back as `intervalStart` to navigate one step into the past.
    """
    field(:previous_interval_start, :date)

    @desc """
    `intervalStart` of the published batch whose start is nearest to one
    pagination step after the current batch. Step size depends on `granularity`.
    `null` when the current batch is the latest one.
    """
    field(:next_interval_start, :date)
  end
end
