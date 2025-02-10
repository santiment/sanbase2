defmodule SanbaseWeb.Graphql.Schema.CommentQueries do
  @moduledoc ~s"""
  Queries and mutations for working with comments
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Middlewares.JWTAuth
  alias SanbaseWeb.Graphql.Resolvers.CommentResolver

  object :comment_queries do
    field :comments_feed, list_of(:comments_feed_item) do
      meta(access: :free)

      arg(:cursor, :cursor_input, default_value: nil)
      arg(:limit, :integer, default_value: 50)

      resolve(&CommentResolver.comments_feed/3)
    end

    field :comments, list_of(:comment) do
      meta(access: :free)

      arg(:entity_type, :comment_entity_type_enum, default_value: :insight)

      arg(:id, :id)
      arg(:cursor, :cursor_input, default_value: nil)
      arg(:limit, :integer, default_value: 50)

      resolve(&CommentResolver.comments/3)
    end

    field :subcomments, list_of(:comment) do
      meta(access: :free)

      arg(:comment_id, non_null(:id))
      arg(:limit, :integer, default_value: 100)

      resolve(&CommentResolver.subcomments/3)
    end
  end

  object :comment_mutations do
    field :create_comment, :comment do
      arg(:entity_type, :comment_entity_type_enum, default_value: :insight)
      arg(:id, :integer)
      arg(:insight_id, non_null(:integer), deprecate: "Use `entityType` + `id` instead")
      arg(:content, non_null(:string))
      arg(:parent_id, :integer)

      middleware(JWTAuth)

      resolve(&CommentResolver.create_comment/3)
    end

    field :update_comment, :comment do
      arg(:comment_id, non_null(:integer))
      arg(:content, non_null(:string))

      middleware(JWTAuth)

      resolve(&CommentResolver.update_comment/3)
    end

    field :delete_comment, :comment do
      arg(:comment_id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&CommentResolver.delete_comment/3)
    end
  end
end
