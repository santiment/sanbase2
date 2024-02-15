defmodule SanbaseWeb.GenericAdmin.Post do
  alias Sanbase.Insight.Post
  def schema_module, do: Post

  def resource do
    %{
      preloads: [:user, :price_chart_project],
      index_fields: [
        :id,
        :title,
        :is_featured,
        :is_pulse,
        :state,
        :ready_state,
        :moderation_comment,
        :user_id
      ],
      edit_fields: [
        :is_featured,
        :is_pulse,
        :is_paywall_required,
        :ready_state,
        :prediction,
        :state,
        :moderation_comment
      ],
      extra_show_fields: [:is_featured],
      field_types: %{
        is_featured: :boolean,
        moderation_comment: :text
      },
      collections: %{
        state:
          [
            Post.awaiting_approval_state(),
            Post.approved_state(),
            Post.declined_state()
          ]
          |> Enum.map(&{&1, &1}),
        ready_state: ~w[published draft],
        prediction: ~w[heavy_bullish semi_bullish semi_bearish heavy_bearish unspecified none]
      },
      funcs: %{
        user_id: &SanbaseWeb.GenericAdmin.User.user_link/1
      }
    }
  end

  def has_many(post) do
    post =
      post
      |> Sanbase.Repo.preload([:tags, :votes])

    [
      %{
        resource: "post_tags",
        resource_name: "Tags",
        rows: post.tags,
        fields: [:name],
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

  def after_filter(post, params) do
    is_featured = params["is_featured"] |> String.to_existing_atom()
    Sanbase.FeaturedItem.update_item(post, is_featured)
  end
end

defmodule SanbaseWeb.GenericAdmin.PostTags do
  import Ecto.Query
  def schema_module, do: Sanbase.Insight.PostTag

  def resource do
    %{
      preloads: [:tag, :post],
      index_fields: [:id, :post_id, :tag_id],
      new_fields: [:post, :tag],
      edit_fields: [:post, :tag],
      belongs_to_fields: %{
        post: %{
          query: from(p in Sanbase.Insight.Post, order_by: [desc: p.id]),
          transform: fn rows -> Enum.map(rows, &{&1.title, &1.id}) end,
          resource: "posts",
          search_fields: [:title]
        },
        tag: %{
          query: from(t in Sanbase.Tag, order_by: [asc: t.name]),
          transform: fn rows -> Enum.map(rows, &{&1.name, &1.id}) end,
          resource: "tags",
          search_fields: [:name]
        }
      },
      field_types: %{},
      funcs: %{}
    }
  end
end

defmodule SanbaseWeb.GenericAdmin.Tag do
  alias Sanbase.Tag
  def schema_module, do: Tag

  def resource do
    %{
      preloads: [],
      index_fields: [:id, :name],
      new_fields: [:name],
      edit_fields: [:name],
      field_types: %{},
      funcs: %{}
    }
  end
end
