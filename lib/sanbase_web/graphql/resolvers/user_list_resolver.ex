defmodule SanbaseWeb.Graphql.Resolvers.UserListResolver do
  require Logger

  alias Sanbase.Auth.User
  alias Sanbase.UserLists.UserList
  alias SanbaseWeb.Graphql.Helpers.Utils
  alias Sanbase.Repo
  alias Sanbase.UserLists.ListItem
  alias Sanbase.Model.Project

  def create_user_list(_root, args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    case UserList.create_user_list(current_user, args) do
      {:ok, user_list} ->
        {:ok, user_list |> Repo.preload(:list_items)}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot create user list", details: Utils.error_details(changeset)
        }
    end
  end

  def update_user_list(_root, %{id: id} = args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    if has_permissions?(id, current_user) do
      case UserList.update_user_list(args) do
        {:ok, user_list} ->
          {:ok, user_list}

        {:error, changeset} ->
          {
            :error,
            message: "Cannot update user list", details: Utils.error_details(changeset)
          }
      end
    else
      {:error, "Cannot update user list"}
    end
  end

  def remove_user_list(_root, %{id: id} = args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    if has_permissions?(id, current_user) do
      case UserList.remove_user_list(args) do
        {:ok, user_list} ->
          {:ok, user_list}

        {:error, changeset} ->
          {
            :error,
            message: "Cannot remove user list", details: Utils.error_details(changeset)
          }
      end
    else
      {:error, "Cannot remove user list"}
    end
  end

  def fetch_user_lists(_root, _args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    case UserList.fetch_user_lists(current_user) do
      {:ok, user_lists} ->
        {:ok, user_lists}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot fetch user lists", details: Utils.error_details(changeset)
        }
    end
  end

  def fetch_public_user_lists(_root, _args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    case UserList.fetch_public_user_lists(current_user) do
      {:ok, user_lists} ->
        {:ok, user_lists}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot fetch public user lists", details: Utils.error_details(changeset)
        }
    end
  end

  def fetch_all_public_user_lists(_root, _args, _resolution) do
    case UserList.fetch_all_public_lists() do
      {:ok, user_lists} ->
        {:ok, user_lists}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot fetch public user lists", details: Utils.error_details(changeset)
        }
    end
  end

  def fetch_public_user_lists_by_id(_root, %{user_list_id: user_list_id}, _resolution) do
    UserList.fetch_public_user_lists_by_id(user_list_id)
  end

  def project_by_list_item(%ListItem{project_id: project_id}, _, _resolution) do
    Project
    |> Repo.get(project_id)
    |> case do
      nil ->
        {:error, "Project with id '#{project_id}' not found."}

      project ->
        project =
          project
          |> Repo.preload([:latest_coinmarketcap_data, icos: [ico_currencies: [:currency]]])

        {:ok, project}
    end
  end

  defp has_permissions?(id, %User{id: user_id}) do
    UserList.by_id(id).user_id == user_id
  end
end
