defmodule SanbaseWeb.Graphql.Schema.ModerationQueries do
  @moduledoc ~s"""
  Queries and mutations for working with Insights
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.ModerationResolver

  object :moderation_queries do
  end

  object :moderation_mutations do
    field :moderate_set_deleted, :boolean do
      arg(:entity_type, non_null(:entity_type))
      arg(:entity_id, non_null(:integer))

      resolve(&ModerationResolver.set_deleted/3)
    end

    field :moderate_unset_deleted, :boolean do
      arg(:entity_type, non_null(:entity_type))
      arg(:entity_id, non_null(:integer))

      resolve(&ModerationResolver.unset_deleted/3)
    end

    field :moderate_unpublish_insight, :boolean do
      arg(:insight_id, non_null(:integer))

      resolve(&ModerationResolver.unpublish_insight/3)
    end
  end
end
