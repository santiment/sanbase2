defmodule SanbaseWeb.GenericAdmin.Comment do
  @behaviour SanbaseWeb.GenericAdmin
  import Ecto.Query
  def schema_module, do: Sanbase.Comment
  def resource_name, do: "comments"
  def singular_resource_name, do: "comment"

  def resource do
    %{
      actions: [:new, :edit, :delete],
      preloads: [:user],
      index_fields: [:id, :user_id, :content],
      new_fields: [:user, :content],
      edit_fields: [:content, :edited_at, :parent_id, :root_parent_id, :subcomments_count],
      belongs_to_fields: %{
        user: SanbaseWeb.GenericAdmin.belongs_to_user(),
        parent_id: %{
          query: from(c in Sanbase.Comment, order_by: [desc: c.id]),
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
      SanbaseWeb.GenericAdmin.resource_link(
        "comments",
        comment.comment_id,
        truncate(comment.comment.content, 60)
      )
    else
      ""
    end
  end

  defp truncate(content, max) when is_binary(content) do
    if String.length(content) > max,
      do: String.slice(content, 0, max) <> "…",
      else: content
  end

  defp truncate(_, _), do: ""
end
