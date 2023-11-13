defmodule SanbaseWeb.Graphql.Resolvers.MenuResolver do
  alias Sanbase.Menus

  # Menu CRUD

  def get_menu(
        _root,
        %{id: menu_id},
        resolution
      ) do
    querying_user_id = get_in(resolution.context.auth, [:current_user, Access.key(:id)])

    case Menus.get_menu(menu_id, querying_user_id) do
      {:ok, menu} -> {:ok, Menus.menu_to_simple_map(menu)}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_menu(_root, %{name: _} = param, %{context: %{auth: %{current_user: current_user}}}) do
    case Menus.create_menu(param, current_user.id) do
      {:ok, menu} -> {:ok, Menus.menu_to_simple_map(menu)}
      {:error, reason} -> {:error, reason}
    end
  end

  def update_menu(_root, %{id: id} = params, %{context: %{auth: %{current_user: current_user}}}) do
    case Menus.update_menu(id, params, current_user.id) do
      {:ok, menu} -> {:ok, Menus.menu_to_simple_map(menu)}
      {:error, reason} -> {:error, reason}
    end
  end

  def delete_menu(_root, %{id: id}, %{context: %{auth: %{current_user: current_user}}}) do
    case Menus.delete_menu(id, current_user.id) do
      {:ok, menu} -> {:ok, Menus.menu_to_simple_map(menu)}
      {:error, reason} -> {:error, reason}
    end
  end

  # MenuItem C~R~UD

  def create_menu_item(_root, %{} = args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    with {:ok, params} <- create_menu_item_params(args) do
      case Menus.create_menu_item(params, current_user.id) do
        {:ok, menu} -> {:ok, Menus.menu_to_simple_map(menu)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def update_menu_item(_root, %{id: id} = params, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    case Menus.update_menu_item(id, params, current_user.id) do
      {:ok, menu} -> {:ok, Menus.menu_to_simple_map(menu)}
      {:error, reason} -> {:error, reason}
    end
  end

  def delete_menu_item(_root, %{id: id}, %{context: %{auth: %{current_user: current_user}}}) do
    case Menus.delete_menu_item(id, current_user.id) do
      {:ok, menu} -> {:ok, Menus.menu_to_simple_map(menu)}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp create_menu_item_params(%{parent_id: parent_id, entity: entity} = args) do
    with {:ok, entity_params} <- entity_to_params(entity) do
      params =
        %{parent_id: parent_id}
        |> Map.merge(entity_params)
        |> Map.merge(Map.take(args, [:position]))

      {:ok, params}
    end
  end

  defp create_menu_item_params(_),
    do:
      {:error,
       "Create menu item parameters are missing the required parent_menu_id and/or entity fields"}

  defp entity_to_params(map) do
    params = Map.reject(map, fn {_k, v} -> is_nil(v) end)

    case map_size(map) do
      1 ->
        {:ok, params}

      _ ->
        {:error, "The entity field must contain exactly one key-value pair with non-null value"}
    end
  end
end
