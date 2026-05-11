defmodule SanbaseWeb.GenericAdmin.Post do
  @behaviour SanbaseWeb.GenericAdmin
  alias Sanbase.Insight.Post

  require Logger
  def schema_module, do: Post
  def resource_name, do: "posts"
  def singular_resource_name, do: "post"

  @index_fields ~w(id title is_featured is_pulse state ready_state moderation_comment user_id)a
  @edit_fields ~w(is_featured is_pulse is_paywall_required ready_state prediction state moderation_comment)a
  def resource do
    %{
      actions: [:edit, :delete],
      preloads: [:user, :price_chart_project],
      index_fields: @index_fields,
      edit_fields: @edit_fields,
      fields_override: %{
        is_featured: %{
          type: :boolean,
          search_query: Post.featured_posts_query()
        },
        user_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.User.user_link/1
        },
        state: %{
          type: :select,
          collection: Post.states()
        },
        ready_state: %{
          type: :select,
          collection: Post.ready_states()
        },
        prediction: %{
          type: :select,
          collection: Post.predictions()
        }
      }
    }
  end

  def has_many(post) do
    post =
      post
      |> Sanbase.Repo.preload([:tags, :votes, :comments, :categories])

    # Get category mappings with source information
    category_mappings = Sanbase.Insight.PostCategory.get_post_categories(post.id)

    # Enrich categories with source information
    enriched_categories =
      Enum.map(post.categories, fn category ->
        mapping = Enum.find(category_mappings, &(&1.category_id == category.id))
        Map.put(category, :source, mapping && mapping.source)
      end)

    [
      %{
        resource: "post_tags",
        resource_name: "Tags",
        rows: post.tags,
        fields: [:name],
        funcs: %{},
        create_link_kv: [linked_resource: :post, linked_resource_id: post.id]
      },
      %{
        resource: "insight_categories",
        resource_name: "Categories",
        rows: enriched_categories,
        fields: [:name, :source],
        funcs: %{},
        create_link_kv: []
      },
      %{
        resource: "post_comments",
        resource_name: "Post Comments",
        rows: post.comments,
        fields: [:id, :comment_id],
        funcs: %{},
        create_link_kv: [linked_resource: :post, linked_resource_id: post.id]
      }
    ]
  end

  def before_filter(post) do
    post = Sanbase.Repo.preload(post, [:featured_item])
    is_featured = if post.featured_item, do: true, else: false

    %{post | is_featured: is_featured}
  end

  def after_filter(post, changeset, params) do
    is_featured = params["is_featured"] |> String.to_existing_atom()
    Sanbase.FeaturedItem.update_item(post, is_featured)

    if changeset.changes[:state] == Post.approved_state() and post.ready_state == Post.published() do
      Logger.info("Publishing insight #{post.id} in discord")
      # If the change is from awaiting_approval/declined to approved and the post is published,
      # send notification in discord.
      # By default, posts are published in awaiting_approval state and only after approval
      # by a moderator they become visible to the public.
      # Posts by santiment team members are auto-approved on publishing and the notification
      # for that is sent from the Post.publish/1 function
      Sanbase.Messaging.Insight.publish_in_discord(post)
    end
  end

  def post_link(row) do
    if row.post_id do
      SanbaseWeb.GenericAdmin.resource_link(
        "posts",
        row.post_id,
        row.post.title
      )
    else
      ""
    end
  end
end
