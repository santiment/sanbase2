defmodule SanbaseWeb.Graphql.EntityTypes do
  use Absinthe.Schema.Notation

  enum :entity_type do
    value(:user_trigger)
    value(:insight)
    value(:project_watchlist)
    value(:address_watchlist)
    value(:screener)
    value(:chart_configuration)
  end

  object :entity_result do
    field(:user_trigger, :user_trigger)
    field(:insight, :post)
    field(:project_watchlist, :user_list)
    field(:address_watchlist, :user_list)
    field(:screener, :user_list)
    field(:chart_configuration, :chart_configuration)
  end
end
