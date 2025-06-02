defmodule SanbaseWeb.Graphql.EntityTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.EntityResolver

  input_object :entity_filter do
    field(:slugs, list_of(:string))
    field(:metrics, list_of(:string))

    @desc ~s"""
    Control whether the public, private or both type of entities are returned.
    Private entities are returned only if the user is the owner of the entity.
    """
    field(:public_status, :entity_public_status)

    field(:insight, :insight_entity_filter)
  end

  input_object :insight_entity_filter do
    field(:tags, list_of(:string))
    field(:paywall, :insight_paywall_filter)
  end

  enum :insight_paywall_filter do
    value(:all)
    value(:paywalled_only)
    value(:non_paywalled_only)
  end

  enum :entity_public_status do
    value(:all)
    value(:public)
    value(:private)
  end

  enum :entity_interaction_interaction_type do
    value(:view)
    value(:upvote)
    value(:downvote)
    value(:comment)
  end

  enum :entity_type do
    value(:address_watchlist)
    value(:chart_configuration)
    value(:dashboard)
    value(:query)
    value(:insight)
    value(:project_watchlist)
    value(:screener)
    value(:user_trigger)
  end

  object :entity_stats do
    field(:total_entities_count, non_null(:integer))
    field(:current_page, non_null(:integer))
    field(:current_page_size, non_null(:integer))
    field(:total_pages_count, non_null(:integer))
  end

  object :single_entity_result do
    field(:address_watchlist, :user_list)
    field(:chart_configuration, :chart_configuration)
    field(:dashboard, :dashboard)
    field(:query, :sql_query)
    field(:insight, :post)
    field(:project_watchlist, :user_list)
    field(:screener, :user_list)
    field(:user_trigger, :user_trigger)
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

  object :most_used_entity_result do
    field :data, list_of(:single_entity_result) do
      resolve(&EntityResolver.get_most_used_data/3)
    end

    field :stats, :entity_stats do
      resolve(&EntityResolver.get_most_used_stats/3)
    end
  end
end
