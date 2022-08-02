defmodule SanbaseWeb.Graphql.CommentTypes do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.{CommentEntityIdResolver, UserResolver}

  enum :comment_entity_type_enum do
    value(:blockchain_address)
    value(:chart_configuration)
    value(:dashboard)
    value(:insight)
    value(:short_url)
    value(:timeline_event)
    value(:watchlist)
  end

  object :comments_feed_item do
    field(:id, non_null(:integer))
    field(:blockchain_address, :blockchain_address_db_stored)
    field(:chart_configuration, :chart_configuration)
    field(:dashboard, :dashboard_schema)
    field(:insight, :post)
    field(:short_url, :short_url)
    field(:timeline_event, :timeline_event)

    field(:content, non_null(:sanitized_html_subset_string))

    field :user, non_null(:public_user) do
      resolve(&UserResolver.user_no_preloads/3)
    end

    field(:parent_id, :integer)
    field(:root_parent_id, :integer)
    field(:subcomments_count, :integer)
    field(:inserted_at, non_null(:datetime))
    field(:edited_at, :datetime)
  end

  object :comment do
    field(:id, non_null(:integer))

    field :insight_id, non_null(:integer) do
      cache_resolve(&CommentEntityIdResolver.insight_id/3)
    end

    field :timeline_event_id, non_null(:integer) do
      cache_resolve(&CommentEntityIdResolver.timeline_event_id/3)
    end

    field :blockchain_address_id, non_null(:integer) do
      cache_resolve(&CommentEntityIdResolver.blockchain_address_id/3)
    end

    field :dashboard_id, non_null(:integer) do
      cache_resolve(&CommentEntityIdResolver.dashboard_id/3)
    end

    field :watchlist_id, non_null(:integer) do
      cache_resolve(&CommentEntityIdResolver.watchlist_id/3)
    end

    field :chart_configuration_id, non_null(:integer) do
      cache_resolve(&CommentEntityIdResolver.chart_configuration_id/3)
    end

    field :short_url_id, non_null(:integer) do
      cache_resolve(&CommentEntityIdResolver.short_url_id/3)
    end

    field(:content, non_null(:sanitized_html_subset_string))

    field :user, non_null(:public_user) do
      resolve(&SanbaseWeb.Graphql.Resolvers.UserResolver.user_no_preloads/3)
    end

    field(:parent_id, :integer)
    field(:root_parent_id, :integer)
    field(:subcomments_count, :integer)
    field(:inserted_at, non_null(:datetime))
    field(:edited_at, :datetime)
  end
end
