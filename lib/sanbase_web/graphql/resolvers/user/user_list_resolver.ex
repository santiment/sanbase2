defmodule SanbaseWeb.Graphql.Resolvers.UserListResolver do
  require Logger

  alias Sanbase.Auth.User
  alias Sanbase.UserList
  alias Sanbase.Model.Project
  alias SanbaseWeb.Graphql.Helpers.Utils

  def historical_stats(
        %UserList{} = user_list,
        %{from: from, to: to, interval: interval},
        _resolution
      ) do
    with measurements when is_list(measurements) <-
           UserList.get_projects(user_list) |> Enum.map(&Sanbase.Influxdb.Measurement.name_from/1),
         {:ok, result} <-
           Sanbase.Prices.Store.fetch_combined_mcap_volume(measurements, from, to, interval) do
      {:ok, result}
    else
      _error -> {:error, "Can't fetch historical stats for a watchlist"}
    end
  end

  def list_items(%UserList{} = user_list, _args, _resolution) do
    result =
      UserList.get_projects(user_list)
      |> Project.preload_assocs()
      |> Enum.map(&%{project: &1})

    {:ok, result}
  end

  def create_user_list(_root, args, %{context: %{auth: %{current_user: current_user}}}) do
    case UserList.create_user_list(current_user, args) do
      {:ok, user_list} ->
        {:ok, user_list}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot create user list", details: Utils.error_details(changeset)
        }
    end
  end

  def update_user_list(_root, %{id: id} = args, %{context: %{auth: %{current_user: current_user}}}) do
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

  def remove_user_list(_root, %{id: id} = args, %{context: %{auth: %{current_user: current_user}}}) do
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
      {:error, "Cannot remove user list belonging to another user"}
    end
  end

  def fetch_user_lists(_root, _args, %{context: %{auth: %{current_user: current_user}}}) do
    UserList.fetch_user_lists(current_user)
  end

  def fetch_user_lists(_root, _args, _resolution) do
    {:error, "Only logged in users can call this method"}
  end

  def fetch_public_user_lists(_root, _args, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserList.fetch_public_user_lists(current_user)
  end

  def fetch_all_public_user_lists(_root, _args, _resolution) do
    UserList.fetch_all_public_lists()
  end

  def watchlist(_root, %{id: id}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserList.user_list(id, current_user)
  end

  def watchlist(_root, %{id: id}, _resolution) do
    UserList.user_list(id, %User{id: nil})
  end

  def user_list(_root, %{user_list_id: user_list_id}, %{
        context: %{auth: %{current_user: current_user}}
      }) do
    UserList.user_list(user_list_id, current_user)
  end

  def user_list(_root, %{user_list_id: user_list_id}, _resolution) do
    UserList.user_list(user_list_id, %User{id: nil})
  end

  defp has_permissions?(id, %User{id: user_id}) do
    UserList.by_id(id).user_id == user_id
  end
end
