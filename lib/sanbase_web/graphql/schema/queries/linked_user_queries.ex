defmodule SanbaseWeb.Graphql.Schema.LinkedUserQueries do
  @moduledoc ~s"""
  """

  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.LinkedUserResolver

  alias SanbaseWeb.Graphql.Middlewares.JWTAuth

  object :linked_user_queries do
    field :get_primary_user, :public_user do
      meta(access: :free)
      middleware(JWTAuth)
      resolve(&LinkedUserResolver.get_primary_user/3)
    end

    field :get_secondary_users, list_of(:public_user) do
      meta(access: :free)
      middleware(JWTAuth)
      resolve(&LinkedUserResolver.get_secondary_users/3)
    end
  end

  object :linked_user_mutations do
    field :generate_linked_user_token, :string do
      meta(access: :free)

      arg(:secondary_user_id, non_null(:integer))

      middleware(JWTAuth)
      resolve(&LinkedUserResolver.generate_linked_users_token/3)
    end

    field :confirm_linked_user_token, :boolean do
      meta(access: :free)

      arg(:token, non_null(:string))

      middleware(JWTAuth)
      resolve(&LinkedUserResolver.confirm_linked_users_token/3)
    end

    field :remove_primary_user, :boolean do
      meta(access: :free)

      arg(:primary_user_id, non_null(:id))

      middleware(JWTAuth)
      resolve(&LinkedUserResolver.remove_primary_user/3)
    end

    field :remove_secondary_user, :boolean do
      meta(access: :free)

      arg(:secondary_user_id, non_null(:id))

      middleware(JWTAuth)
      resolve(&LinkedUserResolver.remove_secondary_user/3)
    end
  end
end
