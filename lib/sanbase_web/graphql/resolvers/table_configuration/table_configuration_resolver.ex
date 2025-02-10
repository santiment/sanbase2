defmodule SanbaseWeb.Graphql.Resolvers.TableConfigurationResolver do
  @moduledoc false
  alias Sanbase.Accounts.User
  alias Sanbase.TableConfiguration

  require Logger

  # Queries

  def table_configuration(_root, %{id: id}, resolution) do
    user = get_in(resolution.context, [:auth, :current_user]) || %User{}
    TableConfiguration.by_id(id, user.id)
  end

  def table_configurations(_root, args, resolution) do
    user = get_in(resolution.context, [:auth, :current_user]) || %User{}

    case args do
      %{user_id: user_id} when not is_nil(user_id) ->
        # All table configurations of user_id accessible by the current user
        {:ok, TableConfiguration.user_table_configurations(user_id, user.id)}

      %{} ->
        # All table configurations accessible by the current user
        {:ok, TableConfiguration.table_configurations(user.id)}
    end
  end

  # Mutations

  def create_table_configuration(_root, %{settings: settings}, %{context: %{auth: %{current_user: user}}}) do
    TableConfiguration.create(Map.put(settings, :user_id, user.id))
  end

  def update_table_configuration(_root, %{id: id, settings: settings}, %{context: %{auth: %{current_user: user}}}) do
    TableConfiguration.update(id, user.id, settings)
  end

  def delete_table_configuration(_root, %{id: id}, %{context: %{auth: %{current_user: user}}}) do
    TableConfiguration.delete(id, user.id)
  end
end
