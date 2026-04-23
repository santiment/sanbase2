defmodule SanbaseWeb.GenericAdmin.UserList do
  @behaviour SanbaseWeb.GenericAdmin
  import Ecto.Query
  def schema_module(), do: Sanbase.UserList
  def resource_name, do: "user_lists"
  def singular_resource_name, do: "user_list"

  def resource do
    %{
      actions: [:edit],
      preloads: [:user],
      index_fields: [:id, :name, :slug, :type, :is_featured, :is_public, :user_id, :function],
      edit_fields: [:name, :slug, :description, :type, :is_public, :is_featured],
      fields_override: %{
        is_featured: %{
          type: :boolean,
          search_query:
            from(
              ul in Sanbase.UserList,
              left_join: featured_item in Sanbase.FeaturedItem,
              on: ul.id == featured_item.user_list_id,
              where: not is_nil(featured_item.id),
              preload: [:user]
            )
            |> distinct(true)
        },
        user_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.User.user_link/1
        },
        function: %{
          value_modifier: fn ul ->
            Map.from_struct(ul.function) |> Jason.encode!(pretty: true)
          end
        },
        type: %{
          type: :select,
          collection: ~w[project blockchain_address]
        }
      }
    }
  end

  def before_filter(user_list) do
    user_list = Sanbase.Repo.preload(user_list, [:featured_item])
    is_featured = if user_list.featured_item, do: true, else: false

    %{user_list | is_featured: is_featured}
  end

  def after_filter(user_list, _changeset, params) do
    is_featured = params["is_featured"] |> String.to_existing_atom()
    Sanbase.FeaturedItem.update_item(user_list, is_featured)
  end

  def user_list_link(row) do
    if row.user_list_id do
      SanbaseWeb.GenericAdmin.resource_link(
        "user_lists",
        row.user_list_id,
        row.user_list.name
      )
    else
      ""
    end
  end
end
