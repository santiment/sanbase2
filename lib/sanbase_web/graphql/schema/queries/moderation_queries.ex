defmodule SanbaseWeb.Graphql.Schema.ModerationQueries do
  @moduledoc ~s"""
  Queries and mutations for working with Insights
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.ModerationResolver
  alias SanbaseWeb.Graphql.Middlewares.JWTModeratorAuth

  object :moderation_queries do
  end

  object :moderation_mutations do
    field :moderate_featured, :boolean do
      arg(:entity_id, non_null(:integer))
      arg(:entity_type, non_null(:entity_type))

      arg(:flag, :boolean, default_value: true)

      middleware(JWTModeratorAuth)

      resolve(&ModerationResolver.moderate_featured/3)
    end

    field :moderate_hide, :boolean do
      arg(:entity_id, non_null(:integer))
      arg(:entity_type, non_null(:entity_type))

      arg(:flag, :boolean, default_value: true)

      middleware(JWTModeratorAuth)

      resolve(&ModerationResolver.moderate_hide/3)
    end

    field :moderate_delete, :boolean do
      arg(:entity_type, non_null(:entity_type))
      arg(:entity_id, non_null(:integer))

      arg(:flag, :boolean, default_value: true)

      middleware(JWTModeratorAuth)

      resolve(&ModerationResolver.moderate_delete/3)
    end

    field :moderate_unpublish_insight, :boolean do
      arg(:insight_id, non_null(:integer))

      middleware(JWTModeratorAuth)

      resolve(&ModerationResolver.unpublish_insight/3)
    end
  end
end
