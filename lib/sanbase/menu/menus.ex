defmodule Sanbase.Menus do
  @moduledoc ~s"""
  Boundary module for working with menus.

  A menu is an ordered list of menu items. Each menu item can be:
    - Query;
    - Dashboard;
    - Menu A sub-menu can also have a list of menu items, in order to build
    nesting and hierarchies.

  When the menu is returned by the GraphQL API, the menu_to_simple_map/1 function
  is used in order to transform the menu struct to a structure that can be directly
  translated to JSON. This menu representation contains only the type, id, name and
  description of each menu item, as well as the position in the menu.
  """
  import Sanbase.Utils.ErrorHandling, only: [changeset_errors_string: 1]

  alias Sanbase.Menus.Menu
  alias Sanbase.Menus.MenuItem
  alias Sanbase.Repo

  @type parent_menu_id :: non_neg_integer()
  @type user_id :: Sanbase.Accounts.User.user_id()
  @type menu_id :: Menu.menu_id()
  @type menu_item_id :: MenuItem.menu_item_id()

  @type create_menu_params :: %{
          required(:name) => String.t(),
          optional(:description) => String.t(),
          optional(:parent_id) => integer(),
          optional(:position) => integer()
        }

  @type update_menu_params :: %{
          optional(:name) => String.t(),
          optional(:description) => String.t()
        }

  @type create_menu_item_params :: %{
          required(:parent_id) => menu_id,
          optional(:position) => integer() | nil,
          optional(:query_id) => Sanbase.Queries.Query.query_id(),
          optional(:dashboard_id) => Sanbase.Dashboards.Dashboard.dashboard_id(),
          optional(:menu_id) => menu_id
        }

  @type update_menu_item_params :: %{
          optional(:parent_id) => menu_id,
          optional(:position) => integer() | nil
        }

  @doc ~s"""
  Get a menu by its id and preloaded 2 levels of nesting.
  """
  def get_menu(menu_id, user_id) do
    query = Menu.by_id(menu_id, user_id)

    case Repo.one(query) do
      nil -> {:error, "Menu with id #{menu_id} not found or it is owned by another user"}
      menu -> {:ok, menu}
    end
  end

  @doc ~s"""
  Convert a menu with preloaded menu items to a map in the format. This format
  can directly be returned by the GraphQL API if the return type is `:json`

  Note: The keys are strings in camelCase, not atoms in snake case. This is because this result
  is directly returned to the API client as a JSON type, which does not go through the
  snake_case => camelCase transformation.

  %{
    "entityType" => :menu, "entityId" 1, "name" => "N", "description" => "D", "menuItems" => [
      %{"entityType" => :query, "entityType" => 2, "name" => "Q", "description" => "D", "position" => 1},
      %{"entityType" => :dashboard, "entityType" => 21, "name" => "D", "description" => "D", "position" => 2}
    ]
  }
  """
  def menu_to_simple_map(%Menu{} = menu) do
    recursively_order_menu_items(%{
      "menuItemId" => nil,
      "entityType" => :menu,
      "entityId" => menu.id,
      "name" => menu.name,
      "description" => menu.description,
      "menuItems" => get_menu_items(menu)
    })

    # If this menu is a sub-menu, then the caller from get_menu_items/1 will
    # additionally set the menu_item_id. If this is the top-level menu, then
    # this is not a sub-menu and it does not have a menu_item_id
  end

  @doc ~s"""
  Create a new menu.

  A menu has a name and a description. It holds a list of MenuItems that have a given
  order. The menu params can also have a `parent_id` and `position` which indicates that this menu
  is created as a sub-menu of that parent.
  """
  @spec create_menu(create_menu_params, user_id) :: {:ok, Menu.t()} | {:error, String.t()}
  def create_menu(params, user_id) do
    params = Map.put(params, :user_id, user_id)

    Ecto.Multi.new()
    |> Ecto.Multi.run(:create_menu, fn _repo, _changes ->
      query = Menu.create(params)
      Repo.insert(query)
    end)
    |> Ecto.Multi.run(:maybe_create_menu_item, fn _repo, %{create_menu: menu} ->
      # If the params have `:parent_id`, then this menu is a sub-menu,
      # which is done by adding a record to the menu_items table.
      case Map.get(params, :parent_id) do
        nil ->
          {:ok, nil}

        parent_id ->
          # Add this new menu as a menu item to the parent
          create_menu_item(
            %{
              parent_id: parent_id,
              menu_id: menu.id,
              position: Map.get(params, :position)
            },
            user_id
          )
      end
    end)
    |> Ecto.Multi.run(:get_menu_with_preloads, fn _repo, %{create_menu: menu} ->
      # There would be no menu items, but this will help to set the menu items to []
      # instead of getting an error when trying to iterate them because they're set to <not preloaded>
      get_menu(menu.id, user_id)
    end)
    |> Repo.transaction()
    |> process_transaction_result(:get_menu_with_preloads)
  end

  @doc ~s"""
  Update an existing menu.

  The name, description, parent_id and position can be updated.
  """
  @spec update_menu(menu_id, update_menu_params, user_id) ::
          {:ok, Menu.t()} | {:error, String.t()}
  def update_menu(menu_id, params, user_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_menu_for_update, fn _repo, _changes ->
      get_menu_for_update(menu_id, user_id)
    end)
    |> Ecto.Multi.run(:update_menu, fn _repo, %{get_menu_for_update: menu} ->
      query = Menu.update(menu, params)
      Repo.update(query)
    end)
    |> Ecto.Multi.run(:get_menu_with_preloads, fn _repo, %{update_menu: menu} ->
      get_menu(menu.id, user_id)
    end)
    |> Repo.transaction()
    |> process_transaction_result(:get_menu_with_preloads)
  end

  @doc ~s"""
  Delete a menu
  """
  @spec delete_menu(menu_id, user_id) :: {:ok, Menu.t()} | {:error, String.t()}
  def delete_menu(menu_id, user_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_menu_for_update, fn _repo, _changes ->
      get_menu_for_update(menu_id, user_id)
    end)
    |> Ecto.Multi.run(:get_menu_with_preloads, fn _repo, _changes ->
      # Call this so we can return the menu with its menu items after it is
      # successfully deleted
      get_menu(menu_id, user_id)
    end)
    |> Ecto.Multi.run(:delete_menu, fn _repo, %{get_menu_for_update: menu} ->
      Repo.delete(menu)
    end)
    |> Repo.transaction()
    # Purposefully do not return the result of the last Ecto.Multi.run call,
    # but from the get_menu_with_preloads call, so we can return the menu with
    # its items.
    |> process_transaction_result(:get_menu_with_preloads)
  end

  @doc ~s"""
  Create a new menu item.

  The menu item can be:
    - Query
    - Dashboard
    - Menu (to build hierarchies)

  Each item has a `position`. If no position is specified, it will be appended at the end.
  If a position is specified, all the positions bigger than it will be bumped by 1 in order
  to accomodate the new item.
  """
  @spec create_menu_item(create_menu_item_params, user_id) ::
          {:ok, Menu.t()} | {:error, String.t()}
  def create_menu_item(params, user_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_menu_for_update, fn _repo, _changes ->
      case Map.get(params, :parent_id) do
        nil ->
          # Early error handling as we need the parent_id before calling the MenuItem.create/1
          # which does the required fields validation
          {:error, "Cannot create a menu item without providing parent_id"}

        parent_id ->
          # Just check that the current user can update the parent menu
          get_menu_for_update(parent_id, user_id)
      end
    end)
    |> Ecto.Multi.run(:get_and_adjust_position, fn _repo, _changes ->
      case Map.get(params, :position) do
        nil ->
          # If `position` is not specified, add it at the end by getting the last position + 1
          get_next_position(params.parent_id)

        position when is_integer(position) ->
          # If `position` is specified, bump all the positions bigger than it by 1 in
          # order to avoid having multiple items with the same position.
          {:ok, {_, nil}} = inc_all_positions_after(params.parent_id, position)

          {:ok, position}
      end
    end)
    |> Ecto.Multi.run(
      :create_menu_item,
      fn _repo, %{get_and_adjust_position: position} ->
        params = Map.merge(params, %{position: position, parent_id: params.parent_id})
        query = MenuItem.create(params)
        Repo.insert(query)
      end
    )
    |> Ecto.Multi.run(:get_menu_with_preloads, fn _repo, %{get_menu_for_update: menu} ->
      get_menu(menu.id, user_id)
    end)
    |> Repo.transaction()
    |> process_transaction_result(:get_menu_with_preloads)
  end

  @doc ~s"""
  Update an existing menu item.

  A menu item can have the follwing fields updated:
    - position - change the position of the item in the menu
    - parent_id - change the parent menu of the item. On the frontend this is done
      by dragging and dropping the item in the menu tree (this can also update the position)

  The entity (query, dashboard, etc.) cannot be changed. Delete a menu item and insert a new
  one instead.
  """
  @spec update_menu_item(menu_item_id, update_menu_item_params, user_id) ::
          {:ok, Menu.t()} | {:error, String.t()}
  def update_menu_item(menu_item_id, params, user_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_menu_item_for_update, fn _repo, _changes ->
      get_menu_item_for_update(menu_item_id, user_id)
    end)
    |> Ecto.Multi.run(
      :adjust_position,
      fn _repo, %{get_menu_item_for_update: menu_item} ->
        case Map.get(params, :position) do
          nil ->
            parent_id = Map.get(params, :parent_id)

            # We cannot change the parent_id without also specifying the position
            if is_nil(parent_id) or parent_id == menu_item.parent_id do
              {:ok, nil}
            else
              {:error, "If the parent_id for a menu item is updated, the position in the new menu must also be specified"}
            end

          position when is_integer(position) ->
            # If `position` is specified, bump all the positions bigger than it by 1 in
            # order to avoid having multiple items with the same position.
            #
            # If the menu gets its parent_id also changed , the bumping
            # must happen in the new parent menu, not in the old one.
            parent_id_after_update = Map.get(params, :parent_id, menu_item.parent_id)

            {:ok, {_, nil}} = inc_all_positions_after(parent_id_after_update, position)
            {:ok, position}
        end
      end
    )
    |> Ecto.Multi.run(:update_menu_item, fn _repo, %{get_menu_item_for_update: menu_item} ->
      query = MenuItem.update(menu_item, params)
      Repo.update(query)
    end)
    |> Ecto.Multi.run(:get_menu_with_preloads, fn _repo, %{update_menu_item: menu_item} ->
      get_menu(menu_item.parent_id, user_id)
    end)
    |> Repo.transaction()
    |> process_transaction_result(:get_menu_with_preloads)
  end

  @doc ~s"""
  Delete a menu item.
  """
  @spec delete_menu_item(menu_item_id, user_id) ::
          {:ok, Menu.t()} | {:error, String.t()}
  def delete_menu_item(menu_item_id, user_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_menu_item, fn _repo, _changes ->
      get_menu_item_for_update(menu_item_id, user_id)
    end)
    |> Ecto.Multi.run(:delete_menu_item, fn _repo, %{get_menu_item: menu_item} ->
      Repo.delete(menu_item)
    end)
    |> Ecto.Multi.run(:get_menu_with_preloads, fn _repo, %{delete_menu_item: menu_item} ->
      get_menu(menu_item.parent_id, user_id)
    end)
    |> Repo.transaction()
    |> process_transaction_result(:get_menu_with_preloads)
  end

  # Private functions

  defp get_menu_for_update(menu_id, user_id) do
    query = Menu.get_for_update(menu_id, user_id)

    case Repo.one(query) do
      nil -> {:error, "Menu with id #{menu_id} not found or it is owned by another user"}
      menu -> {:ok, menu}
    end
  end

  defp get_menu_item_for_update(menu_item_id, user_id) do
    query = MenuItem.get_for_update(menu_item_id, user_id)

    case Repo.one(query) do
      nil ->
        {:error, "Menu item with id #{menu_item_id} not found or it is part of a menu owned by another user"}

      menu ->
        {:ok, menu}
    end
  end

  defp get_next_position(menu_id) do
    query = MenuItem.get_next_position(menu_id)

    {:ok, Repo.one(query)}
  end

  defp inc_all_positions_after(menu_id, position) do
    query = MenuItem.inc_all_positions_after(menu_id, position)
    {:ok, Repo.update_all(query, [])}
  end

  defp process_transaction_result({:ok, map}, ok_field), do: {:ok, map[ok_field]}

  defp process_transaction_result({:error, _, %Ecto.Changeset{} = changeset, _}, _ok_field),
    do: {:error, changeset_errors_string(changeset)}

  defp process_transaction_result({:error, _, error, _}, _ok_field), do: {:error, error}

  # Helpers for transforming a menu struct to a simple map
  defp recursively_order_menu_items(%{"menuItems" => menu_items} = map) do
    sorted_menu_items =
      menu_items
      |> Enum.sort_by(& &1["position"], :asc)
      |> Enum.map(fn
        %{"menuItems" => [_ | _]} = elem -> recursively_order_menu_items(elem)
        x -> x
      end)

    %{map | "menuItems" => sorted_menu_items}
  end

  defp recursively_order_menu_items(data), do: data

  defp get_menu_items(%Menu{menu_items: []}), do: []

  defp get_menu_items(%Menu{menu_items: list}) when is_list(list) do
    Enum.map(list, fn
      %{id: menu_item_id, query: %{} = map, position: position} ->
        %{
          "name" => map.name,
          "description" => map.description,
          "entityType" => :query,
          "entityId" => map.id,
          "position" => position,
          "menuItemId" => menu_item_id
        }

      %{id: menu_item_id, dashboard: %{} = map, position: position} ->
        Map.take(map, [:name, :description])

        %{
          "name" => map.name,
          "description" => map.description,
          "entityType" => :dashboard,
          "entityId" => map.id,
          "position" => position,
          "menuItemId" => menu_item_id
        }

      %{id: menu_item_id, menu: %{} = map, position: position} ->
        map
        |> menu_to_simple_map()
        |> Map.merge(%{
          "name" => map.name,
          "description" => map.description,
          "entityType" => :menu,
          "entityId" => map.id,
          "position" => position,
          "menuItemId" => menu_item_id
        })
    end)
  end
end
