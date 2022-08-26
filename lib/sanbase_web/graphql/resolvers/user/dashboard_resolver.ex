defmodule SanbaseWeb.Graphql.Resolvers.DashboardResolver do
  @moduledoc ~s"""
  Module with resolvers connected to the Apikey authentication. All the logic
  is delegated to the `Apikey` module
  """
  import Absinthe.Resolution.Helpers, except: [async: 1]
  import SanbaseWeb.Graphql.Helpers.Utils, only: [resolution_to_user_id_or_nil: 1]

  alias Sanbase.Dashboard
  alias SanbaseWeb.Graphql.SanbaseDataloader

  require Logger

  def get_clickhouse_database_metadata(_root, _args, _resolution) do
    Dashboard.Autocomplete.get_data()
  end

  def user_public_dashboards(%Sanbase.Accounts.User{} = user, _args, _resolution) do
    Dashboard.get_user_public_dashboard_schemas(user.id)
  end

  def user_dashboards(%Sanbase.Accounts.User{} = user, _args, _resolution) do
    Dashboard.get_user_dashboard_schemas(user.id)
  end

  def get_available_clickhouse_tables(_root, _args, _resolution) do
    tables = Dashboard.Database.Table.get_tables()
    {:ok, tables}
  end

  def create_dashboard(_root, args, %{context: %{auth: %{current_user: user}}}) do
    Dashboard.create(args, user.id)
  end

  def update_dashboard(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with true <- is_dashboard_owner?(args.id, user.id),
         {:ok, dashboard_schema} <- Dashboard.update(args.id, args) do
      {:ok, atomize_panel_sql_keys(dashboard_schema)}
    end
  end

  def delete_dashboard(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with true <- is_dashboard_owner?(args.id, user.id) do
      Dashboard.delete(args.id)
    end
  end

  def create_dashboard_panel(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with true <- is_dashboard_owner?(args.dashboard_id, user.id),
         {:ok, %{} = result} <- Dashboard.create_panel(args.dashboard_id, args.panel) do
      {:ok, result.panel |> Map.put(:dashboard_id, result.dashboard.id)}
    end
  end

  def remove_dashboard_panel(_root, args, %{context: %{auth: %{current_user: user}}}) do
    %{dashboard_id: dashboard_id, panel_id: panel_id} = args

    with true <- is_dashboard_owner?(dashboard_id, user.id),
         {:ok, %{} = result} <- Dashboard.remove_panel(dashboard_id, panel_id) do
      {:ok, result.panel |> Map.put(:dashboard_id, dashboard_id)}
    end
  end

  def update_dashboard_panel(_root, args, %{context: %{auth: %{current_user: user}}}) do
    %{dashboard_id: dashboard_id, panel_id: panel_id, panel: panel} = args

    with true <- is_dashboard_owner?(dashboard_id, user.id),
         {:ok, %{} = result} <- Dashboard.update_panel(dashboard_id, panel_id, panel) do
      {:ok, result.panel |> Map.put(:dashboard_id, dashboard_id)}
    end
  end

  def compute_dashboard_panel(_root, args, %{context: %{auth: %{current_user: user}}}) do
    %{dashboard_id: dashboard_id, panel_id: panel_id} = args

    with true <- can_view_dashboard?(dashboard_id, user.id),
         true <- can_run_computation?(user.id) do
      Dashboard.compute_panel(dashboard_id, panel_id, user.id)
    end
  end

  def compute_and_store_dashboard_panel(_root, args, %{context: %{auth: %{current_user: user}}}) do
    %{dashboard_id: dashboard_id, panel_id: panel_id} = args
    # storing requires edit access, not just view access
    with true <- is_dashboard_owner?(dashboard_id, user.id),
         true <- can_run_computation?(user.id) do
      Dashboard.compute_and_store_panel(dashboard_id, panel_id, user.id)
    end
  end

  def store_dashboard_panel(_root, args, %{context: %{auth: %{current_user: user}}}) do
    %{dashboard_id: dashboard_id, panel_id: panel_id, panel: panel} = args
    # storing requires edit access, not just view access
    compressed_rows = Dashboard.Query.rows_to_compressed_rows(panel.rows)
    panel = Map.put(panel, :compressed_rows, compressed_rows)

    with true <- is_dashboard_owner?(dashboard_id, user.id),
         %{} = query_result <- struct!(Dashboard.Query.Result, panel),
         {:ok, _} <- Dashboard.Cache.update_panel_cache(dashboard_id, panel_id, query_result) do
      panel_cache = Dashboard.Panel.Cache.from_query_result(query_result, panel_id, dashboard_id)
      {:ok, panel_cache}
    end
  end

  def get_clickhouse_query_execution_stats(
        _root,
        %{clickhouse_query_id: clickhouse_query_id},
        %{context: %{auth: %{current_user: user}}}
      ) do
    case Dashboard.QueryExecution.get_execution_stats(user.id, clickhouse_query_id) do
      {:ok, stats} ->
        execution_details = %{
          cpu_time_microseconds: stats.execution_details["cpu_time_microseconds"],
          memory_usage_gb: stats.execution_details["memory_usage_gb"],
          query_duration_ms: stats.execution_details["query_duration_ms"],
          read_compressed_gb: stats.execution_details["read_compressed_gb"],
          read_gb: stats.execution_details["read_gb"],
          read_rows: stats.execution_details["read_rows"],
          result_gb: stats.execution_details["result_gb"],
          result_rows: stats.execution_details["result_rows"]
        }

        result =
          stats
          |> Map.from_struct()
          |> Map.take([:credits_cost, :query_start_time, :query_end_time])
          |> Map.merge(execution_details)

        {:ok, result}

      {:error, error} ->
        {:error, error}
    end
  end

  def get_dashboard_schema(_root, args, resolution) do
    user_id_or_nil = resolution_to_user_id_or_nil(resolution)

    with true <- can_view_dashboard?(args.id, user_id_or_nil),
         {:ok, dashboard_schema} <- Dashboard.load_schema(args.id) do
      {:ok, atomize_panel_sql_keys(dashboard_schema)}
    end
  end

  def get_dashboard_cache(_root, args, resolution) do
    user_id_or_nil = resolution_to_user_id_or_nil(resolution)

    with true <- can_view_dashboard?(args.id, user_id_or_nil),
         {:ok, dashboard_cache} <- Dashboard.load_cache(args.id) do
      panels =
        Enum.map(dashboard_cache.panels, fn {panel_id, panel_cache} ->
          Map.put(panel_cache, :id, panel_id)
        end)

      {:ok, %{dashboard_cache | panels: panels}}
    end
  end

  def get_dashboard_panel_cache(_root, args, resolution) do
    user_id_or_nil = resolution_to_user_id_or_nil(resolution)

    with true <- can_view_dashboard?(args.dashboard_id, user_id_or_nil),
         {:ok, panel_cache} <- Dashboard.load_panel_cache(args.dashboard_id, args.panel_id) do
      {:ok, panel_cache}
    end
  end

  def compute_raw_clickhouse_query(_root, args, %{context: %{auth: %{current_user: user}}}) do
    san_query_id = UUID.uuid4()

    with true <- can_run_computation?(user.id),
         true <- Dashboard.Query.valid_sql?(args),
         {:ok, query_result} <-
           Dashboard.Query.run(args.query, args.parameters, san_query_id, user.id) do
      Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
        Dashboard.QueryExecution.store_execution(user.id, query_result)
      end)

      {:ok, query_result}
    end
  end

  def get_dashboard_schema_history_list(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with true <- is_dashboard_owner?(args.id, user.id) do
      opts = [page: args.page, page_size: args.page_size]
      Dashboard.History.get_history_list(args.id, opts)
    end
  end

  def get_dashboard_schema_history(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with true <- is_dashboard_owner?(args.id, user.id),
         {:ok, dashboard_schema_history} <- Dashboard.History.get_history(args.id, args.hash) do
      {:ok, atomize_panel_sql_keys(dashboard_schema_history)}
    end
  end

  def store_dashboard_schema_history(_root, args, %{context: %{auth: %{current_user: user}}}) do
    with true <- is_dashboard_owner?(args.id, user.id),
         {:ok, dashboard} <- Dashboard.load_schema(args.id) do
      Dashboard.History.commit(dashboard, args.message)
    end
  end

  def comments_count(%{id: id}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :dashboard_comments_count, id)
    |> on_load(fn loader ->
      count = Dataloader.get(loader, SanbaseDataloader, :dashboard_comments_count, id)
      {:ok, count || 0}
    end)
  end

  # Private functions

  defp can_view_dashboard?(id, user_id) do
    # Users can see their own dashboard and other people's public dashboards

    case Dashboard.get_is_public_and_owner(id) do
      {:ok, %{user_id: ^user_id}} -> true
      {:ok, %{is_public: true}} -> true
      _ -> {:error, "Dashboard is private or does not exist"}
    end
  end

  defp is_dashboard_owner?(id, user_id) do
    case Dashboard.get_is_public_and_owner(id) do
      {:ok, %{user_id: ^user_id}} ->
        true

      _ ->
        {:error, "Dashboard does not exist or it's not owned by the user."}
    end
  end

  defp can_run_computation?(user_id) do
    case Dashboard.has_credits_left?(user_id) do
      true -> true
      false -> {:error, "The user with id #{user_id} has no credits left"}
    end
  end

  defp atomize_panel_sql_keys(struct) do
    panels =
      Enum.map(struct.panels, fn
        %{sql: %{} = sql} = panel ->
          atomized_sql = Map.new(sql, fn {k, v} -> {String.to_existing_atom(k), v} end)

          %{panel | sql: atomized_sql}

        panel ->
          panel
      end)

    struct
    |> Map.put(:panels, panels)
  end
end
