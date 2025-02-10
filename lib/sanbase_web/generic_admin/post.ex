defmodule SanbaseWeb.GenericAdmin.Post do
  @moduledoc false
  import Ecto.Query

  alias Sanbase.Insight.Post

  def schema_module, do: Post

  @index_fields ~w(id title is_featured is_pulse state ready_state moderation_comment user_id)a
  @edit_fields ~w(is_featured is_pulse is_paywall_required ready_state prediction state moderation_comment)a
  def resource do
    %{
      actions: [:edit],
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
    post = Sanbase.Repo.preload(post, [:tags, :votes, :comments])

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
    is_featured = String.to_existing_atom(params["is_featured"])
    Sanbase.FeaturedItem.update_item(post, is_featured)
  end

  def post_link(row) do
    if row.post_id do
      SanbaseWeb.GenericAdmin.Subscription.href(
        "posts",
        row.post_id,
        row.post.title
      )
    else
      ""
    end
  end
end

defmodule SanbaseWeb.GenericAdmin.PostTags do
  @moduledoc false
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
      }
    }
  end
end

defmodule SanbaseWeb.GenericAdmin.Tag do
  @moduledoc false
  alias Sanbase.Tag

  def schema_module, do: Tag

  def resource do
    %{
      actions: [:new, :edit],
      preloads: [],
      index_fields: [:id, :name],
      new_fields: [:name],
      edit_fields: [:name]
    }
  end
end

defmodule SanbaseWeb.GenericAdmin.PostComment do
  @moduledoc false
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
      fields_override: %{
        comment_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.Comment.comment_link/1
        },
        post_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.Post.post_link/1
        }
      }
    }
  end
end

defmodule SanbaseWeb.GenericAdmin.Comment do
  @moduledoc false
  import Ecto.Query

  def schema_module, do: Sanbase.Comment

  def resource do
    %{
      actions: [:new, :edit],
      preloads: [:user],
      index_fields: [:id, :user_id, :content],
      new_fields: [:user, :content],
      edit_fields: [:content, :edited_at, :parent_id, :root_parent_id, :subcomments_count, :user],
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
      },
      fields_override: %{
        content: %{
          type: :text
        },
        user_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.User.user_link/1
        }
      }
    }
  end

  def comment_link(comment) do
    if comment.comment do
      SanbaseWeb.GenericAdmin.Subscription.href(
        "comments",
        comment.comment_id,
        comment.comment.content
      )
    else
      ""
    end
  end
end

defmodule SanbaseWeb.GenericAdmin.UserTrigger do
  @moduledoc false
  import Ecto.Query

  alias Sanbase.Alert.UserTrigger

  def schema_module, do: UserTrigger

  def resource do
    %{
      actions: [:edit],
      preloads: [:user],
      index_fields: [:id, :user_id, :trigger],
      edit_fields: [:user, :is_public, :is_featured],
      belongs_to_fields: %{
        user: %{
          query: from(u in Sanbase.Accounts.User, order_by: [desc: u.id]),
          transform: fn rows -> Enum.map(rows, &{&1.email, &1.id}) end,
          resource: "users",
          search_fields: [:email, :username]
        }
      },
      fields_override: %{
        user_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.User.user_link/1
        },
        trigger: %{
          value_modifier: fn trigger ->
            trigger |> Map.from_struct() |> Jason.encode!(pretty: true)
          end
        },
        is_featured: %{
          type: :boolean,
          search_query:
            distinct(
              from(ut in UserTrigger,
                left_join: featured_item in Sanbase.FeaturedItem,
                on: ut.id == featured_item.user_trigger_id,
                where: not is_nil(featured_item.id),
                preload: [:user]
              ),
              true
            )
        }
      }
    }
  end

  def before_filter(trigger) do
    trigger = Sanbase.Repo.preload(trigger, [:featured_item])
    is_featured = if trigger.featured_item, do: true, else: false

    %{
      trigger
      | is_featured: is_featured,
        is_public: UserTrigger.public?(trigger)
    }
  end

  # TODO propagate errors from before/after filters to users
  def after_filter(trigger, params) do
    trigger =
      trigger
      |> UserTrigger.update_changeset(%{
        trigger: %{is_public: String.to_existing_atom(params["is_public"])}
      })
      |> Sanbase.Repo.update!()

    is_featured = String.to_existing_atom(params["is_featured"])
    Sanbase.FeaturedItem.update_item(trigger, is_featured)
  end
end

defmodule SanbaseWeb.GenericAdmin.ChartConfiguration do
  @moduledoc false
  def schema_module, do: Sanbase.Chart.Configuration
  def resource_name, do: "chart_configurations"

  def resource do
    %{
      actions: [:new, :edit],
      preloads: [:user, :project],
      index_fields: [:id, :title, :is_public, :user_id],
      new_fields: [:title, :is_public],
      edit_fields: [:title, :is_public],
      fields_override: %{
        user_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.User.user_link/1
        },
        project_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.Project.project_link/1
        }
      }
    }
  end
end

defmodule SanbaseWeb.GenericAdmin.TableConfiguration do
  @moduledoc false
  def schema_module, do: Sanbase.TableConfiguration

  def resource do
    %{
      actions: [:new, :edit],
      preloads: [:user],
      index_fields: [:id, :title, :is_public, :user_id],
      new_fields: [:title, :is_public],
      edit_fields: [:title, :is_public],
      fields_override: %{
        user_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.User.user_link/1
        }
      }
    }
  end
end
