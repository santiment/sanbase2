defmodule SanbaseWeb.GenericAdmin.Post do
  alias Sanbase.Insight.Post
  def schema_module, do: Post

  def resource do
    %{
      actions: [:edit],
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
      |> Sanbase.Repo.preload([:tags, :votes, :comments])

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

  def after_filter(post, params) do
    is_featured = params["is_featured"] |> String.to_existing_atom()
    Sanbase.FeaturedItem.update_item(post, is_featured)
  end

  def post_link(row) do
    SanbaseWeb.GenericAdmin.Subscription.href(
      "posts",
      row.post_id,
      row.post.title
    )
  end
end

defmodule SanbaseWeb.GenericAdmin.PostTags do
  import Ecto.Query
  def schema_module, do: Sanbase.Insight.PostTag

  def resource do
    %{
      actions: [:new, :edit],
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
      actions: [:new, :edit],
      preloads: [],
      index_fields: [:id, :name],
      new_fields: [:name],
      edit_fields: [:name],
      field_types: %{},
      funcs: %{}
    }
  end
end

defmodule SanbaseWeb.GenericAdmin.PostComment do
  import Ecto.Query
  def schema_module, do: Sanbase.Comment.PostComment

  def resource do
    %{
      actions: [:new, :edit],
      preloads: [:comment, :post],
      index_fields: [:id, :post_id, :comment_id],
      new_fields: [:post, :comment],
      edit_fields: [:post, :comment],
      belongs_to_fields: %{
        post: %{
          query: from(p in Sanbase.Insight.Post, order_by: [desc: p.id]),
          transform: fn rows -> Enum.map(rows, &{&1.title, &1.id}) end,
          resource: "posts",
          search_fields: [:title]
        },
        comment: %{
          query: from(c in Sanbase.Comment, order_by: [desc: c.id]),
          transform: fn rows -> Enum.map(rows, &{&1.content, &1.id}) end,
          resource: "comments",
          search_fields: [:content]
        }
      },
      field_types: %{},
      funcs: %{
        post_id: &SanbaseWeb.GenericAdmin.Post.post_link/1,
        comment_id: &SanbaseWeb.GenericAdmin.Comment.comment_link/1
      }
    }
  end
end

defmodule SanbaseWeb.GenericAdmin.Comment do
  import Ecto.Query
  def schema_module, do: Sanbase.Comment

  def resource do
    %{
      actions: [:new, :edit],
      preloads: [:user],
      index_fields: [:id, :user_id, :content],
      new_fields: [:user, :content],
      edit_fields: [:content, :edited_at, :parent_id, :root_parent_id, :subcomments_count, :user],
      field_types: %{
        content: :text
      },
      funcs: %{
        user_id: &SanbaseWeb.GenericAdmin.User.user_link/1
      },
      belongs_to_fields: %{
        user: %{
          query: from(u in Sanbase.Accounts.User, order_by: [desc: u.id]),
          transform: fn rows -> Enum.map(rows, &{&1.email, &1.id}) end,
          resource: "users",
          search_fields: [:email, :username]
        },
        parent_id: %{
          query: from(c in Sanbase.Comment, where: is_nil(c.parent_id), order_by: [desc: c.id]),
          transform: fn rows -> Enum.map(rows, &{&1.content, &1.id}) end,
          resource: "comments",
          search_fields: [:content]
        },
        root_parent_id: %{
          query: from(c in Sanbase.Comment, where: is_nil(c.parent_id), order_by: [desc: c.id]),
          transform: fn rows -> Enum.map(rows, &{&1.content, &1.id}) end,
          resource: "comments",
          search_fields: [:content]
        }
      }
    }
  end

  def comment_link(comment) do
    SanbaseWeb.GenericAdmin.Subscription.href(
      "comments",
      comment.comment_id,
      comment.comment.content
    )
  end
end
