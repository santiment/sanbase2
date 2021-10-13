defmodule SanbaseWeb.Graphql.Schema.InsightQueries do
  @moduledoc ~s"""
  Queries and mutations for working with Insights
  """
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.{
    InsightResolver,
    FileResolver
  }

  alias SanbaseWeb.Graphql.Middlewares.JWTAuth
  alias SanbaseWeb.Graphql.Middlewares.PostPaywallFilter

  object :insight_queries do
    field :popular_insight_authors, list_of(:public_user) do
      meta(access: :free)

      cache_resolve(&InsightResolver.popular_insight_authors/3)
    end

    @desc ~s"""
    Fetch the post with the given ID.
    The user must be logged in to access all fields for the post/insight.
    """
    field :post, :post do
      meta(access: :free)

      deprecate("Use `insight` instead")
      arg(:id, non_null(:integer))

      resolve(&InsightResolver.post/3)
      middleware(PostPaywallFilter)
    end

    @desc ~s"""
    Fetch the insight with the given ID.
    The user must be logged in to access all fields for the post/insight.
    """
    field :insight, :post do
      meta(access: :free)

      arg(:id, non_null(:integer))

      resolve(&InsightResolver.post/3)
      middleware(PostPaywallFilter)
    end

    @desc """
    Fetch a list of all posts/insights.
    Optionally a list of tags can be passed so it fetches all insights with these tags.
    It supports paginations with `page` and `page_size` args.
    """
    field :all_insights, list_of(:post) do
      meta(access: :free)

      arg(:page, :integer, default_value: 1)
      arg(:page_size, :integer, default_value: 20)
      arg(:tags, list_of(:string))
      arg(:is_pulse, :boolean)
      arg(:is_paywall_required, :boolean)
      arg(:from, :datetime)
      arg(:to, :datetime)

      resolve(&InsightResolver.all_insights/3)
      middleware(PostPaywallFilter)
    end

    @desc "Fetch a list of all posts for given user ID."
    field :all_insights_for_user, list_of(:post) do
      meta(access: :free)

      arg(:user_id, non_null(:integer))
      arg(:is_pulse, :boolean)
      arg(:is_paywall_required, :boolean)
      arg(:from, :datetime)
      arg(:to, :datetime)
      arg(:page, :integer, default_value: 1)
      arg(:page_size, :integer, default_value: 20)

      resolve(&InsightResolver.all_insights_for_user/3)
      middleware(PostPaywallFilter)
    end

    @desc "Fetch a list of all posts for which a user has voted."
    field :all_insights_user_voted, list_of(:post) do
      meta(access: :free)

      arg(:user_id, non_null(:integer))
      arg(:is_pulse, :boolean)
      arg(:is_paywall_required, :boolean)
      arg(:from, :datetime)
      arg(:to, :datetime)

      resolve(&InsightResolver.all_insights_user_voted_for/3)
      middleware(PostPaywallFilter)
    end

    @desc ~s"""
    Fetch a list of all posts/insights that have a given tag.
    The user must be logged in to access all fields for the post/insight.
    """
    field :all_insights_by_tag, list_of(:post) do
      meta(access: :free)

      arg(:tag, non_null(:string))
      arg(:is_pulse, :boolean)
      arg(:is_paywall_required, :boolean)
      arg(:from, :datetime)
      arg(:to, :datetime)

      resolve(&InsightResolver.all_insights_by_tag/3)
      middleware(PostPaywallFilter)
    end

    field :all_insights_by_search_term, list_of(:post) do
      meta(access: :free)

      arg(:search_term, non_null(:string))
      arg(:is_pulse, :boolean)
      arg(:is_paywall_required, :boolean)
      arg(:from, :datetime)
      arg(:to, :datetime)

      cache_resolve(&InsightResolver.all_insights_by_search_term/3, ttl: 5, max_ttl_offset: 5)
      middleware(PostPaywallFilter)
    end

    field :all_insights_by_search_term_highlighted, list_of(:post_search) do
      meta(access: :free)

      arg(:search_term, non_null(:string))
      arg(:is_pulse, :boolean)
      arg(:is_paywall_required, :boolean)
      arg(:from, :datetime)
      arg(:to, :datetime)
      arg(:page, :integer, default_value: 1)
      arg(:page_size, :integer, default_value: 10)

      cache_resolve(&InsightResolver.all_insights_by_search_term_highlighted/3,
        ttl: 5,
        max_ttl_offset: 5
      )

      middleware(PostPaywallFilter)
    end

    @desc "Fetch a list of all tags used for posts/insights. This query also returns tags that are not yet in use."
    field :all_tags, list_of(:tag) do
      meta(access: :free)

      cache_resolve(&InsightResolver.all_tags/3)
    end

    field :insight_comments, list_of(:comment) do
      deprecate("deprecated in favor of `comments` with `entityType` argument as INSIGHT")

      meta(access: :free)

      arg(:insight_id, non_null(:id))
      arg(:cursor, :cursor_input, default_value: nil)
      arg(:limit, :integer, default_value: 50)

      resolve(&InsightResolver.insight_comments/3)
    end
  end

  object :insight_mutations do
    @desc """
    Create a post. After creation the post is not visible to anyone but the author.
    To be visible to anyone, the post must be published. By publishing it also becomes
    immutable and can no longer be updated.
    """
    field :create_post, :post do
      deprecate("Use `createInsight` instead")
      arg(:title, non_null(:string))
      arg(:short_desc, :string)
      arg(:link, :string)
      arg(:text, :string)
      arg(:image_urls, list_of(:string))
      arg(:tags, list_of(:string))
      arg(:is_pulse, :boolean)
      arg(:is_paywall_required, :boolean)

      middleware(JWTAuth)
      resolve(&InsightResolver.create_post/3)
    end

    @desc """
    Create an insight. After creation the insight is not visible to anyone but the author.
    To be visible to anyone, the insight must be published. By publishing it also becomes
    immutable and can no longer be updated.
    """
    field :create_insight, :post do
      arg(:title, non_null(:string))
      arg(:short_desc, :string)
      arg(:link, :string)
      arg(:text, :string)
      arg(:image_urls, list_of(:string))
      arg(:tags, list_of(:string))
      arg(:is_pulse, :boolean)
      arg(:is_paywall_required, :boolean)
      arg(:prediction, :string)
      arg(:metrics, list_of(:string))
      arg(:price_chart_project_id, :integer)

      middleware(JWTAuth)
      resolve(&InsightResolver.create_post/3)
    end

    @desc """
    Update a post if and only if the currently logged in user is the creator of the post
    A post can be updated if it is not yet published.
    """
    field :update_post, :post do
      deprecate("Use `updateInsight` instead")
      arg(:id, non_null(:id))
      arg(:title, :string)
      arg(:short_desc, :string)
      arg(:link, :string)
      arg(:text, :string)
      arg(:image_urls, list_of(:string))
      arg(:tags, list_of(:string))
      arg(:is_pulse, :boolean)
      arg(:is_paywall_required, :boolean)

      middleware(JWTAuth)
      resolve(&InsightResolver.update_post/3)
    end

    @desc """
    Update an insight if and only if the currently logged in user is the creator of the insight
    An insight can be updated if it is not yet published.
    """
    field :update_insight, :post do
      arg(:id, non_null(:id))
      arg(:title, :string)
      arg(:short_desc, :string)
      arg(:link, :string)
      arg(:text, :string)
      arg(:image_urls, list_of(:string))
      arg(:tags, list_of(:string))
      arg(:is_pulse, :boolean)
      arg(:is_paywall_required, :boolean)
      arg(:prediction, :string)
      arg(:metrics, list_of(:string))
      arg(:price_chart_project_id, :integer)

      middleware(JWTAuth)
      resolve(&InsightResolver.update_post/3)
    end

    @desc "Delete a post. The post must be owned by the user currently logged in."
    field :delete_post, :post do
      deprecate("Use `deleteInsight` instead")

      arg(:id, non_null(:id))

      middleware(JWTAuth)
      resolve(&InsightResolver.delete_post/3)
    end

    @desc "Delete an insight. The insight must be owned by the user currently logged in."
    field :delete_insight, :post do
      arg(:id, non_null(:id))

      middleware(JWTAuth)
      resolve(&InsightResolver.delete_post/3)
    end

    @desc "Upload a list of images and return their URLs."
    field :upload_image, list_of(:image_data) do
      arg(:images, list_of(:upload))

      middleware(JWTAuth)
      resolve(&FileResolver.upload_image/3)
    end

    @desc """
    Publish insight. The `id` argument must be an id of an already existing insight.
    Once published, the insight is visible to anyone and can no longer be edited.
    """
    field :publish_insight, :post do
      arg(:id, non_null(:id))

      middleware(JWTAuth)
      resolve(&InsightResolver.publish_insight/3)
    end

    @desc """
    Vote for an insight. The user must logged in.
    """
    field :vote, :post do
      arg(:post_id, :integer, deprecate: "Use `insightId` instead")
      arg(:insight_id, :integer)
      middleware(JWTAuth)
      resolve(&InsightResolver.vote/3)
    end

    @desc """
    Remove your vote for an insight. The user must logged in.
    """
    field :unvote, :post do
      arg(:post_id, :integer, deprecate: "Use `insightId` instead")
      arg(:insight_id, :integer)
      middleware(JWTAuth)
      resolve(&InsightResolver.unvote/3)
    end

    @desc """
    Create an insight connected to particular chart configuration
    """
    field :create_chart_event, :post do
      arg(:chart_configuration_id, non_null(:id))
      arg(:chart_event_datetime, non_null(:datetime))
      arg(:title, non_null(:string))
      arg(:text, non_null(:string))

      middleware(JWTAuth)
      resolve(&InsightResolver.create_chart_event/3)
    end
  end
end
