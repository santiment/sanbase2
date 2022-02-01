defmodule SanbaseWeb.Graphql.Resolvers.ChartConfigurationResolver do
  import Absinthe.Resolution.Helpers, except: [async: 1]

  alias Sanbase.Chart.Configuration
  alias Sanbase.Accounts.User
  alias SanbaseWeb.Graphql.SanbaseDataloader

  require Logger

  # Queries

  def chart_configuration(_root, %{id: id}, resolution) do
    user = get_in(resolution.context, [:auth, :current_user]) || %User{}
    Configuration.by_id(id, querying_user_id: user.id)
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

  def get_chart_configuration_shared_access_token(
        _root,
        %{chart_configuration_id: id},
        %{context: %{auth: %{current_user: user}}}
      ) do
    with {_, true} <-
           {:sanbase_pro?, Sanbase.Billing.Subscription.user_has_sanbase_pro?(user.id)},
         {:ok, %Configuration{} = config} <- Configuration.by_id(id, querying_user_id: user.id),
         true <- user_can_get_shared_access_token?(config, user.id),
         {:ok, shared_access_token} <- get_or_generate_shared_access_token(config) do
      {:ok, shared_access_token}
    else
      {:sanbase_pro?, false} ->
        {:error,
         "Generating a Shared Access Token from a chart layout is allowed only for Sanbase Pro users."}

      error ->
        error
    end
  end

  defp get_or_generate_shared_access_token(config) do
    case Configuration.SharedAccessToken.by_chart_configuration_id(config.id) do
      {:ok, token} ->
        {:ok, token}

      {:error, _} ->
        case Configuration.SharedAccessToken.generate(config) do
          {:ok, token} -> {:ok, token}
          {:error, error} -> {:error, error}
        end
    end
  end

  defp user_can_get_shared_access_token?(config, user_id) do
    case config do
      %Configuration{user_id: ^user_id, is_public: true} ->
        true

      %Configuration{user_id: ^user_id, is_public: false} ->
        {:error, "Shared Access Token can be created only for a public chart configuration."}
    end
  end

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

  def comments_count(%{id: id}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :chart_configuration_comments_count, id)
    |> on_load(fn loader ->
      count = Dataloader.get(loader, SanbaseDataloader, :chart_configuration_comments_count, id)
      {:ok, count || 0}
    end)
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
