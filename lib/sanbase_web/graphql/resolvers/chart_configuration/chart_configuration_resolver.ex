defmodule SanbaseWeb.Graphql.Resolvers.ChartConfigurationResolver do
  @moduledoc false
  import Absinthe.Resolution.Helpers, except: [async: 1]

  alias Sanbase.Accounts.User
  alias Sanbase.Chart.Configuration
  alias SanbaseWeb.Graphql.SanbaseDataloader

  require Logger

  # Queries

  def chart_configuration(_root, %{id: id}, resolution) do
    user = get_in(resolution.context, [:auth, :current_user]) || %User{}
    Configuration.by_id(id, querying_user_id: user.id)
  end

  def chart_configurations(_root, args, resolution) do
    with %User{} = user <- get_in(resolution.context, [:auth, :current_user]) || %User{},
         {:ok, args} <- transform_project_slug_to_id(args),
         :ok <- validate_only_one_selector(args) do
      case args do
        %{chart_configuration_ids: chart_configuration_ids} ->
          # TODO: Improve the response format consistency of the Configuration functions.
          Configuration.by_ids(chart_configuration_ids, user_id_has_access: user.id)

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

  def get_chart_configuration_shared_access_token(_root, %{chart_configuration_id: id}, %{
        context: %{auth: %{current_user: user}}
      }) do
    with {_, true} <-
           {:sanbase_pro?, Sanbase.Billing.Subscription.user_has_sanbase_pro?(user.id)},
         {:ok, %Configuration{} = config} <- Configuration.by_id(id, querying_user_id: user.id),
         true <- user_can_get_shared_access_token?(config, user.id),
         {:ok, shared_access_token} <- get_or_generate_shared_access_token(config) do
      {:ok, shared_access_token}
    else
      {:sanbase_pro?, false} ->
        {:error, "Generating a Shared Access Token from a chart layout is allowed only for Sanbase Pro users."}

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

  def create_chart_configuration(_root, %{settings: settings}, %{context: %{auth: %{current_user: user}}}) do
    Configuration.create(Map.put(settings, :user_id, user.id))
  end

  def update_chart_configuration(_root, %{id: id, settings: settings}, %{context: %{auth: %{current_user: user}}}) do
    Configuration.update(id, user.id, settings)
  end

  def delete_chart_configuration(_root, %{id: id}, %{context: %{auth: %{current_user: user}}}) do
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

  defp transform_project_slug_to_id(%{project_id: _, project_slug: _}) do
    {:error, "Both projectId and projectSlug arguments are provided. Please use only one of them or none."}
  end

  defp transform_project_slug_to_id(%{project_id: _} = args) do
    {:ok, args}
  end

  defp transform_project_slug_to_id(%{project_slug: slug} = args) do
    project_id = Sanbase.Project.id_by_slug(slug)

    args =
      args
      |> Map.delete(:project_slug)
      |> Map.put(:project_id, project_id)

    {:ok, args}
  end

  defp transform_project_slug_to_id(args), do: {:ok, args}

  defp validate_only_one_selector(args) do
    # This is called AFTER transform_project_slug_to_id/2, so no checks for project_slug
    # are needed here.
    cond do
      map_size(args) == 1 and Map.has_key?(args, :project_id) ->
        :ok

      map_size(args) == 1 and Map.has_key?(args, :user_id) ->
        :ok

      map_size(args) == 2 and Map.has_key?(args, :user_id) and Map.has_key?(args, :project_id) ->
        :ok

      map_size(args) == 1 and Map.has_key?(args, :chart_configuration_ids) ->
        :ok

      map_size(args) == 0 ->
        :ok

      true ->
        {:error,
         "Too many arguments provided. Please use only one of the following arguments: " <>
           "project_slug, project_id, user_id, chart_configuration_ids, or the combination of user_id and project_id"}
    end
  end
end
