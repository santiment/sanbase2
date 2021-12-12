defmodule SanbaseWeb.Graphql.EntityTypes do
  use Absinthe.Schema.Notation

  enum :entity_type do
    value(:insight)
    value(:watchlist)
    value(:screener)
    value(:timeline_event)
    value(:chart_configuration)
  end

  object :entity_result do
    field(:insight, :post)
    field(:watchlist, :user_list)
    field(:screener, :user_list)
    field(:timeline_event, :timeline_event)
    field(:chart_configuration, :chart_configuration)
  end
end
