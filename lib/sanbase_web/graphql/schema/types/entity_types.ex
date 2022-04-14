defmodule SanbaseWeb.Graphql.EntityTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.EntityResolver

  enum :entity_type do
    value(:user_trigger)
    value(:insight)
    value(:project_watchlist)
    value(:address_watchlist)
    value(:screener)
    value(:chart_configuration)
  end

  object :entity_stats do
    field(:total_entities_count, non_null(:integer))
    field(:current_page, non_null(:integer))
    field(:current_page_size, non_null(:integer))
  end

  object :single_entity_result do
    field(:user_trigger, :user_trigger)
    field(:insight, :post)
    field(:project_watchlist, :user_list)
    field(:address_watchlist, :user_list)
    field(:screener, :user_list)
    field(:chart_configuration, :chart_configuration)
  end

  object :most_voted_entity_result do
    field :data, list_of(:single_entity_result) do
      resolve(&EntityResolver.get_most_voted_data/3)
    end

    field :stats, :entity_stats do
      resolve(&EntityResolver.get_most_voted_stats/3)
    end
  end

  object :most_recent_entity_result do
    field :data, list_of(:single_entity_result) do
      resolve(&EntityResolver.get_most_recent_data/3)
    end

    field :stats, :entity_stats do
      resolve(&EntityResolver.get_most_recent_stats/3)
    end
  end
end
