defmodule SanbaseWeb.Graphql.MajorTopicsTypes do
  @moduledoc false
  use Absinthe.Schema.Notation

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
    field(:interval_start, non_null(:date))
    field(:interval_end, non_null(:date))
    field(:published_at, :datetime)

    @desc "X-axis labels formatted as `dd.mm.yy`, in chronological order. Aligned with each dataset's `data` list."
    field(:labels, non_null(list_of(non_null(:string))))

    field(:datasets, non_null(list_of(non_null(:major_topic_dataset))))
  end
end
