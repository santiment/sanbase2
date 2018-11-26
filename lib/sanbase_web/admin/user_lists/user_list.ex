defmodule Sanbase.ExAdmin.UserLists.UserList do
  use ExAdmin.Register

  alias Sanbase.UserLists.UserList

  register_resource Sanbase.UserLists.UserList do
    form user do
      inputs do
        input(user, :name)
        input(user, :is_public)
      end
    end

    show user_list do
      attributes_table

      panel "List items" do
        table_for Sanbase.Repo.preload(user_list.list_items, [:project]) do
          column(:project, link: true)
        end
      end
    end
  end
end
