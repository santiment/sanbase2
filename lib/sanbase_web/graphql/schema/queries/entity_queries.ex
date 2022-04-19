defmodule SanbaseWeb.Graphql.Schema.EntityQueries do
  @moduledoc ~s"""
  Queries and mutations for working with Insights
  """
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.EntityResolver

  object :entity_queries do
    field :get_most_voted, :most_voted_entity_result do
      meta(access: :free)
      arg(:type, :entity_type)
      arg(:types, list_of(:entity_type))
      arg(:page, :integer)
      arg(:page_size, :integer)
      arg(:current_user_data_only, :boolean, default_value: false)
      arg(:cursor, :cursor_input_no_order, default_value: nil)
      arg(:filter, :entity_filter)

      cache_resolve(&EntityResolver.get_most_voted/3, ttl: 30, max_ttl_offset: 30)
    end

    field :get_most_recent, :most_recent_entity_result do
      meta(access: :free)

      arg(:type, :entity_type)
      arg(:types, list_of(:entity_type))
      arg(:page, :integer)
      arg(:page_size, :integer)
      arg(:current_user_data_only, :boolean, default_value: false)
      arg(:cursor, :cursor_input_no_order, default_value: nil)
      arg(:filter, :entity_filter)

      resolve(&EntityResolver.get_most_recent/3)
    end
  end

  object :entity_mutations do
  end
end
