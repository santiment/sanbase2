defmodule SanbaseWeb.GenericAdmin.PostComment do
  @behaviour SanbaseWeb.GenericAdmin
  import Ecto.Query
  def schema_module, do: Sanbase.Comment.PostComment
  def resource_name, do: "post_comments"
  def singular_resource_name, do: "post_comment"

  def resource do
    %{
      actions: [:new, :edit, :delete],
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
