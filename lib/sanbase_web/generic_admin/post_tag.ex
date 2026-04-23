defmodule SanbaseWeb.GenericAdmin.PostTags do
  @behaviour SanbaseWeb.GenericAdmin
  import Ecto.Query
  def schema_module, do: Sanbase.Insight.PostTag
  def resource_name, do: "post_tags"
  def singular_resource_name, do: "post_tag"

  def resource do
    %{
      actions: [:new, :edit, :delete],
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
