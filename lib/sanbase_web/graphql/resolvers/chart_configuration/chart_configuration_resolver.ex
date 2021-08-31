defmodule SanbaseWeb.Graphql.Resolvers.ChartConfigurationResolver do
  alias Sanbase.Chart.Configuration
  alias Sanbase.Accounts.User

  require Logger

  # Queries

  def chart_configuration(_root, %{id: id}, resolution) do
    user = get_in(resolution.context, [:auth, :current_user]) || %User{}
    Configuration.by_id(id, user.id)
  end

  def chart_configurations(_root, args, resolution) do
    with %User{} = user <- get_in(resolution.context, [:auth, :current_user]) || %User{},
         {:ok, project_id} <- get_project_id_from_args(args) do
      # Update the project_id if it is not nil. This will reduce the slug case
      # down to project_id case and handle them the same way
      args = if project_id, do: Map.put(args, :project_id, project_id), else: args

      case args do
        %{user_id: user_id, project_id: project_id}
        when not is_nil(user_id) and not is_nil(project_id) ->
          # All configurations of user_id for project_id accessible by the current user
          {:ok, Configuration.user_configurations(user_id, user.id, project_id)}

        %{user_id: user_id} when not is_nil(user_id) ->
          # All configurations of user_id accessible by the current user
          {:ok, Configuration.user_configurations(user_id, user.id)}

        %{project_id: project_id} when not is_nil(project_id) ->
          # All configurations of project_id accessible by the current user
          {:ok, Configuration.project_configurations(project_id, user.id)}

        %{} ->
          # All configurations accessible by the current user
          {:ok, Configuration.configurations(user.id)}
      end
    end
  end

  # Mutations

  def create_chart_configuration(
        _root,
        %{settings: settings},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Configuration.create(Map.put(settings, :user_id, user.id))
  end

  def update_chart_configuration(
        _root,
        %{id: id, settings: settings},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Configuration.update(id, user.id, settings)
  end

  def delete_chart_configuration(
        _root,
        %{id: id},
        %{context: %{auth: %{current_user: user}}}
      ) do
    Configuration.delete(id, user.id)
  end

  # Private functions

  defp get_project_id_from_args(%{project_id: _, project_slug: _}) do
    {:error,
     "Both projectId and projectSlug arguments are provided. Please use only one of them or none."}
  end

  defp get_project_id_from_args(%{project_id: project_id}) do
    {:ok, project_id}
  end

  defp get_project_id_from_args(%{project_slug: slug}) do
    {:ok, Sanbase.Model.Project.id_by_slug(slug)}
  end

  defp get_project_id_from_args(_), do: {:ok, nil}
end
