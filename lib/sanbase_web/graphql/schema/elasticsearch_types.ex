defmodule SanbaseWeb.Graphql.ElasticsearchTypes do
  use Absinthe.Schema.Notation

  object :elasticsearch_stats do
    field(:documents_count, non_null(:integer))
    field(:size_in_megabytes, non_null(:integer))
    field(:telegram_channels_count, non_null(:integer))
    field(:subreddits_count, non_null(:integer))
    field(:average_documents_per_day, non_null(:integer))
  end
end
