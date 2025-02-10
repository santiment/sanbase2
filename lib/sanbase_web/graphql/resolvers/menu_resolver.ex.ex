defmodule SanbaseWeb.Graphql.Resolvers.MenuResolver do
  @moduledoc false
  alias Sanbase.Menus

  # Menu CRUD
  defp maybe_transform_menu({:ok, menu}) do
    transformed_menu = Menus.menu_to_simple_map(menu)
    {:ok, transformed_menu}
  end

  defp maybe_transform_menu({:error, reason}) do
    {:error, reason}
  end

  def get_menu(_root, %{id: menu_id}, resolution) do
    querying_user_id = get_in(resolution.context.auth, [:current_user, Access.key(:id)])

    menu_id
    |> Menus.get_menu(querying_user_id)
    |> maybe_transform_menu()
  end

  def create_menu(_root, %{name: _} = param, %{context: %{auth: %{current_user: current_user}}}) do
    param
    |> Menus.create_menu(current_user.id)
    |> maybe_transform_menu()
  end

  def update_menu(_root, %{id: id} = params, %{context: %{auth: %{current_user: current_user}}}) do
    id
    |> Menus.update_menu(params, current_user.id)
    |> maybe_transform_menu()
  end

  def delete_menu(_root, %{id: id}, %{context: %{auth: %{current_user: current_user}}}) do
    id
    |> Menus.delete_menu(current_user.id)
    |> maybe_transform_menu()
  end

  # MenuItem C~R~UD

  def create_menu_item(_root, %{} = args, %{context: %{auth: %{current_user: current_user}}}) do
    with {:ok, params} <- create_menu_item_params(args) do
      params
      |> Menus.create_menu_item(current_user.id)
      |> maybe_transform_menu()
    end
  end

  def update_menu_item(_root, %{id: id} = params, %{context: %{auth: %{current_user: current_user}}}) do
    id
    |> Menus.update_menu_item(params, current_user.id)
    |> maybe_transform_menu()
  end

  def delete_menu_item(_root, %{id: id}, %{context: %{auth: %{current_user: current_user}}}) do
    id
    |> Menus.delete_menu_item(current_user.id)
    |> maybe_transform_menu()
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
    do: {:error, "Create menu item parameters are missing the required parent_menu_id and/or entity fields"}

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
