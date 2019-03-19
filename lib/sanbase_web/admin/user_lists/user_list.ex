defmodule Sanbase.ExAdmin.UserList do
  use ExAdmin.Register

  alias Sanbase.UserList

  register_resource Sanbase.UserList do
    update_changeset(:update_changeset)
    action_items(only: [:show, :edit, :delete])

    index do
      column(:id)
      column(:name)
      column(:is_featured, &is_featured(&1))
      column(:is_public)
      column(:user)
    end

    form user_list do
      inputs do
        input(user_list, :name)
        input(user_list, :is_public)

        input(
          user_list,
          :is_featured,
          collection: ~w(true false)
        )
      end
    end

    show user_list do
      attributes_table do
        row(:id)
        row(:name)
        row(:is_public)
        row(:is_featured, &is_featured(&1))
        row(:color)
        row(:user, link: true)
      end

      panel "List items" do
        table_for Sanbase.Repo.preload(user_list.list_items, [:project]) do
          column(:project, link: true)
        end
      end
    end

    controller do
      after_filter(:set_featured, only: [:update])
    end
  end

  defp is_featured(%UserList{} = ul) do
    ut = Sanbase.Repo.preload(ul, [:featured_item])
    (ut.featured_item != nil) |> Atom.to_string()
  end

  def set_featured(conn, params, resource, :update) do
    is_featured = params.user_list.is_featured |> String.to_existing_atom()
    Sanbase.FeaturedItem.update_item(resource, is_featured)
    {conn, params, resource}
  end
end
